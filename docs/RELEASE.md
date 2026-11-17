# Сборка и публикация релиза

## 1. Что нужно

- Официальный архив `Mod-Constructor-v5.0-beta.15.1.zip` из [релиза Zerbu](https://github.com/Zerbu/Mod-Constructor-5/releases/tag/v5-beta.15.1).
- Рабочая папка с локализованными файлами (текущая русская сборка).
- PowerShell 5.1 или новее.
- Python 3.7 или новее (для ZIP с прямыми слэшами).
- Свободное место около 150 МБ.

Скрипт не скачивает официальный архив сам: путь к нему передаётся явно, чтобы сборка не зависела от доступности GitHub.

## 2. Сборка

Из корня репозитория:

```powershell
.\tools\build-release.ps1 `
  -BaseZip "C:\path\to\Mod-Constructor-v5.0-beta.15.1.zip" `
  -PatchRoot "C:\path\to\Mod-Constructor-v5.0-beta.15.1-RU"
```

Результат:

```text
dist/Mod-Constructor-v5.0-beta.15.1-RU.zip
```

Скрипт:

1. Распаковывает официальный архив во временную папку.
2. Проверяет, что все файлы из `manifest/localization-manifest.json` есть в `PatchRoot`.
3. Копирует только эти файлы, сохраняя структуру папок.
4. Проверяет SHA256 каждого скопированного файла.
5. Добавляет README, NOTICE, CHANGELOG и генерирует `BUILD_INFO.txt`.
6. Считает `checksums.sha256` для всего релиза.
7. Упаковывает папку в ZIP с именами файлов через `/` (Python `zipfile`) и проверяет, что в архиве нет обратных слэшей.

Если хотя бы один файл отсутствует или его хеш не совпадает, сборка останавливается. Это защищает от случайного попадания старых DLL или неполного набора пресетов.

## 3. Проверка

Распакуйте ZIP в отдельную папку и запустите:

```powershell
.\tools\verify-release.ps1 `
  -ReleaseDir "C:\path\to\Mod-Constructor-v5.0-beta.15.1-RU" `
  -ManifestPath ".\manifest\localization-manifest.json"
```

Скрипт проверяет:

- наличие обязательных файлов;
- отсутствие `.original`, `.before_*`, `Presets_Backup*`, `.zip` и других служебных файлов;
- хеши изменённых DLL и пресетов;
- `checksums.sha256`;
- отсутствие локальных путей вида `C:\Users\<name>` в текстовых файлах.

Дополнительно вручную:

- запустить `Constructor5.exe` из распакованной папки;
- открыть существующий проект;
- создать тестовый проект и сохранить его;
- выполнить экспорт одного простого мода в `%TEMP%`, а не в рабочую папку `Mods`;
- убедиться, что `.package` создался и не пустой.

Чек-лист: [TESTING.md](TESTING.md).

## 4. Публикация на GitHub

Репозиторий должен содержать только текстовые файлы, скрипты и манифест. ZIP и распакованную сборку в Git не добавляйте.

1. Создайте репозиторий, например `sims4-mod-constructor-ru`.
2. Загрузите содержимое этого каталога, кроме `dist/`.
3. Создайте Release с тегом `v5.0-beta.15.1-ru.1`.
4. Название: `Russian localization v5.0-beta.15.1-ru.1`.
5. Прикрепите `dist/Mod-Constructor-v5.0-beta.15.1-RU.zip` как asset.
6. Вставьте в описание:

```text
Base: Zerbu/Mod-Constructor-5 v5-beta.15.1
Upstream commit: ab7df5b0aa89a9d2e74054653093ee33a04ab10f
Localization revision: 1
SHA256: <hash of zip>
```

7. Проверьте, что архив скачивается и открывается.

Если используется GitHub CLI:

```powershell
gh release create v5.0-beta.15.1-ru.1 `
  ".\dist\Mod-Constructor-v5.0-beta.15.1-RU.zip" `
  --title "Russian localization v5.0-beta.15.1-ru.1" `
  --notes-file ".\docs\RELEASE_NOTES.ru.1.md"
```

`gh` должен быть установлен и авторизован. Если его нет, используйте веб-интерфейс GitHub: Releases → Draft a new release → прикрепить ZIP.

## 5. После публикации

- Проверьте скачивание архива по ссылке из Release.
- Сверьте SHA256 у скачанного файла с указанным в описании.
- Обновите `CHANGELOG.md`, если были правки.
- Не добавляйте в релиз личные проекты, логи, настройки и резервные копии.

## 6. Если меняются файлы

1. Обновите локализованные файлы в `PatchRoot`.
2. Пересчитайте `manifest/localization-manifest.json`:

```powershell
.\tools\update-manifest.ps1 `
  -BaseZip "C:\path\to\Mod-Constructor-v5.0-beta.15.1.zip" `
  -PatchRoot "C:\path\to\Mod-Constructor-v5.0-beta.15.1-RU"
```

3. Пересоберите релиз и проверьте его заново.
4. Поднимите ревизию: `ru.2`, `ru.3` и т.д.
