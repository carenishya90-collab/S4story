# Автоматическое исправление Python-инъекции MC5

## Проблема

Mod Constructor 5 генерирует для social-миксеров такой код:

```python
@inject_to(InstanceManager, 'load_data_into_class_instances')
def ..._AddMixer_...(original, self, packs_to_load=None):
    original(self, packs_to_load)
```

В игре 1.116.240.1020 у `InstanceManager.load_data_into_class_instances` только один аргумент — `self`. Вызов `original(self, packs_to_load)` даёт:

```text
TypeError: load_data_into_class_instances() takes 1 positional argument but 2 were given
```

Из-за этого не инициализируется `tuning_instance_manager`; при заселении игра уходит в бесконечную загрузку или выбрасывает на выбор городов. Ошибка подтверждена в `lastException_63930760434.txt` (Pride) и `lastException_63930844381.txt` (Greed).

## Основное решение: автопатч при экспорте

Установлен автоматический хук в пользовательский `site-packages` Python 3.7:

```text
C:\Users\User\AppData\Roaming\Python\Python37\site-packages\
    mc5_autopatch.py
    usercustomize.py
```

`usercustomize.py` загружается при каждом запуске Python 3.7. `mc5_autopatch.py` перехватывает `py_compile.compile()`, который вызывает `python -m compileall` во время экспорта MC5. Перед компиляцией он:

- находит в сгенерированном `.py` шаблон `packs_to_load`;
- заменяет сигнатуру на `*args, **kwargs`;
- заменяет вызов на `original(self, *args, **kwargs)`;
- сохраняет файл обратно;
- дальше MC5 компилирует уже исправленный `.py` в `.pyc` и пакует оба файла в `.ts4script`.

Итог: **после обычного экспорта MC5 ничего вручную патчить не нужно**. Хук работает и при экспорте из GUI, и через `ExportProject.exe` / `ExportProjectInvariant.exe`.

Проверено реальным экспортом Greed:

```text
Compiling 'S4Story_GreedTrait.py'...
EXPORT_DONE
```

В журнале:

```text
2026-11-21 14:05:01 PATCHED S4Story_GreedTrait.py defs=2 calls=2
```

В полученном `.ts4script` нет `packs_to_load`, `.pyc` читается через `zipimport`.

Журнал: `Projects\_Tools\mc5_autopatch.log`.

## Если Python 3.7 переустановили

Скопировать хук заново:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\User\Documents\The Sims 4 Mod Constructor\Projects\_Tools\install_mc5_autopatch.ps1"
```

Скрипт не перезаписывает чужой `usercustomize.py`: если файл уже есть, он добавляет только строку `import mc5_autopatch`.

## Резервный ручной патч

Если хук недоступен (другая машина, другой Python, старый уже собранный `.ts4script`), можно пропатчить файл вручную:

```powershell
python "C:\Users\User\Documents\The Sims 4 Mod Constructor\Projects\_Tools\patch_mc5_ts4script.py" "C:\путь\к\Мод.ts4script"
```

Скрипт заменяет проблемный код, пересобирает `.pyc`, синхронизирует timestamp и проверяет `zipimport`.

## Где уже применено

- `S4Story_PrideTrait\dist\S4Story_PrideTrait.ts4script` — SHA256 `13FFCF4F3958003EBDA22C94AB8FB9C03BE0A133E09629FA8D62E3C6B28EE45C`.
- `S4Story_GreedTrait\dist\S4Story_GreedTrait.ts4script` — SHA256 `47D3F0ED966C87730A7793B5151BA43EABFAB412342589676EBFCD91F3BF635A`.
- `S4Story_DarkCovenCareer` и `S4Story_ShesterkaCareer` тоже содержат этот шаблон; при следующем экспорте автопатч исправит их `.ts4script` сам.

## Что не менялось

- `Constructor5.Base.dll`, `Constructor5.Elements.dll` и русская локализация MC5 не изменялись.
- Пакеты `.package` не изменяются.
- Хук срабатывает только на файлы, где одновременно есть `packs_to_load` и `load_data_into_class_instances`; обычные Python-файлы не затрагиваются.
