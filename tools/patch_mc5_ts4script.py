import argparse
import copy
import hashlib
import os
import py_compile
import re
import struct
import sys
import tempfile
import time
import zipfile
import zipimport


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def patch_source(text):
    text, n_defs = re.subn(
        r'def (\w+)\(original, self, packs_to_load=None\):',
        r'def \1(original, self, *args, **kwargs):',
        text)
    text, n_calls = re.subn(
        r'(?m)^([ \t]+)original\(self, packs_to_load\)[ \t]*\r?$',
        r'\1original(self, *args, **kwargs)',
        text)
    if 'packs_to_load' in text:
        raise RuntimeError('packs_to_load still present after patching')
    return text, n_defs, n_calls


def compile_source(source_bytes, module_name, work_dir, timestamp):
    src_path = os.path.join(work_dir, module_name + '.py')
    pyc_path = os.path.join(work_dir, module_name + '.pyc')
    with open(src_path, 'wb') as f:
        f.write(source_bytes)
    os.utime(src_path, (timestamp, timestamp))
    py_compile.compile(src_path, cfile=pyc_path, doraise=True)
    with open(pyc_path, 'rb') as f:
        pyc_bytes = f.read()
    if len(pyc_bytes) < 16:
        raise RuntimeError('compiled pyc is too short')
    magic, flags, mtime, size = struct.unpack('<IIII', pyc_bytes[:16])
    if mtime != timestamp:
        raise RuntimeError('pyc mtime %r does not match requested %r' % (mtime, timestamp))
    if size != len(source_bytes):
        raise RuntimeError('pyc source size %r does not match %r' % (size, len(source_bytes)))
    return pyc_bytes


def patch_script(path):
    path = os.path.abspath(path)
    if not os.path.isfile(path):
        raise FileNotFoundError(path)
    print('FILE', path)
    print('BEFORE SHA256', sha256_file(path))

    with zipfile.ZipFile(path, 'r') as zin:
        infos = zin.infolist()
        names = [i.filename for i in infos]
        data = {name: zin.read(name) for name in names}

    py_names = [n for n in names if n.endswith('.py') and not n.startswith('__pycache__/')]
    if not py_names:
        raise RuntimeError('no .py files in archive')

    # A timestamp with an even number of seconds is representable by ZIP's DOS timestamp.
    timestamp = int(time.time()) // 2 * 2
    zip_date_time = time.localtime(timestamp)[:6]
    print('ZIP TIMESTAMP', zip_date_time, 'EPOCH', timestamp)

    patched = {}
    pyc_data = {}
    total_defs = 0
    total_calls = 0
    with tempfile.TemporaryDirectory(prefix='mc5patch_') as work_dir:
        for name in py_names:
            raw = data[name]
            text = raw.decode('utf-8-sig')
            fixed, n_defs, n_calls = patch_source(text)
            total_defs += n_defs
            total_calls += n_calls
            fixed_bytes = fixed.encode('utf-8')
            patched[name] = fixed_bytes
            module_name = name[:-3].replace('/', '.')
            pyc_name = name[:-3] + '.pyc'
            if '/' in pyc_name:
                # Nested modules are not expected here; keep the archive layout intact.
                work_module_name = os.path.basename(name)[:-3]
            else:
                work_module_name = module_name
            pyc_data[pyc_name] = compile_source(fixed_bytes, work_module_name, work_dir, timestamp)
            print('PATCHED %s defs=%d calls=%d py=%d pyc=%d' % (
                name, n_defs, n_calls, len(fixed_bytes), len(pyc_data[pyc_name])))

    if total_defs == 0 and total_calls == 0:
        raise RuntimeError('expected AddMixer injection code was not found')

    out_fd, out_path = tempfile.mkstemp(prefix='mc5patch_', suffix='.ts4script', dir=os.path.dirname(path))
    os.close(out_fd)
    try:
        with zipfile.ZipFile(out_path, 'w') as zout:
            written = set()
            for info in infos:
                name = info.filename
                if name in patched:
                    payload = patched[name]
                    new_info = copy.copy(info)
                    new_info.date_time = zip_date_time
                    zout.writestr(new_info, payload)
                    written.add(name)
                elif name in pyc_data:
                    payload = pyc_data[name]
                    new_info = copy.copy(info)
                    new_info.date_time = zip_date_time
                    zout.writestr(new_info, payload)
                    written.add(name)
                else:
                    zout.writestr(info, data[name])
                    written.add(name)
            # Add .pyc entries that did not exist in the source archive.
            for pyc_name, payload in sorted(pyc_data.items()):
                if pyc_name in written:
                    continue
                new_info = zipfile.ZipInfo(pyc_name, zip_date_time)
                new_info.compress_type = zipfile.ZIP_DEFLATED
                zout.writestr(new_info, payload)

        with zipfile.ZipFile(out_path, 'r') as z:
            check_names = z.namelist()
            for name in py_names:
                text = z.read(name).decode('utf-8-sig')
                if 'packs_to_load' in text:
                    raise RuntimeError('patched archive still contains packs_to_load in ' + name)
                compile(text, name, 'exec')
            for pyc_name in pyc_data:
                if pyc_name not in check_names:
                    raise RuntimeError('missing ' + pyc_name)
                payload = z.read(pyc_name)
                magic, flags, mtime, size = struct.unpack('<IIII', payload[:16])
                if mtime != timestamp:
                    raise RuntimeError('archive pyc mtime mismatch for ' + pyc_name)
        # Verify the compiled pyc is usable by zipimport without the .py source.
        with tempfile.TemporaryDirectory(prefix='mc5check_') as check_dir:
            for pyc_name, payload in pyc_data.items():
                module_name = os.path.basename(pyc_name)[:-4]
                check_path = os.path.join(check_dir, module_name + '.zip')
                with zipfile.ZipFile(check_path, 'w', zipfile.ZIP_DEFLATED) as check_zip:
                    check_zip.writestr(os.path.basename(pyc_name), payload)
                code = zipimport.zipimporter(check_path).get_code(module_name)
                if code is None:
                    raise RuntimeError('zipimport could not read ' + pyc_name)
        os.replace(out_path, path)
        out_path = None
    finally:
        if out_path and os.path.exists(out_path):
            os.remove(out_path)

    print('AFTER SHA256', sha256_file(path))
    print('OK', path)


def main():
    parser = argparse.ArgumentParser(description='Patch MC5 .ts4script InstanceManager injection for the current game.')
    parser.add_argument('paths', nargs='+')
    args = parser.parse_args()
    for path in args.paths:
        patch_script(path)


if __name__ == '__main__':
    main()
