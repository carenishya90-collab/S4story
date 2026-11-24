# Russian localization v5.0-beta.15.1-ru.2

Неофициальная русская сборка The Sims 4 Mod Constructor V5.

- База: [Zerbu/Mod-Constructor-5](https://github.com/Zerbu/Mod-Constructor-5) `v5-beta.15.1`
- Upstream commit: `ab7df5b0aa89a9d2e74054653093ee33a04ab10f`
- Ревизия локализации: `ru.2`
- Дата: 24.11.2026
- Размер архива: 39 711 385 байт
- SHA256 архива: `2034f2e0fde5edb6d45d1b99b9ecdaf01570622d2bf177f14aa5992d9decd5a6`

## Что в этом релизе

Главное — исправление генерации Python-скриптов (`.ts4script`) при экспорте модов:

- **Инъекции `InstanceManager.load_data_into_class_instances`** (карьеры и супервзаимодействия, социальные миксеры, наборы лута, режиссёры зон, расширения наборов желаний и перечислений): генерировалась сигнатура `(original, self, packs_to_load=None)` с вызовом `original(self, packs_to_load)`. Начиная с игры 1.116.240.1020 это давало `TypeError` и ломало загрузку тюнингов (бесконечная загрузка или вылет на выбор города). Исправлено на `(original, self, *args, **kwargs)`.
- **Инъекция `SimInfoManager.on_loading_screen_animation_finished` у триггеров действия (ActionTrigger)**: функция получала `original` и никогда его не вызывала, полностью подменяя метод игры (в игре — отправка всей семьи в поездку при отправке одного сима). Теперь `original` вызывается, тело обёрнуто в `try/except`, результат возвращается.
- Реализация: `Tools/mc5_autopatch.py` — хук `py_compile.compile()`, исправляет `.py` до компиляции `.pyc` (работает и при GUI-экспорте, и через `ExportProject.exe` / `ExportProjectInvariant.exe`); `Tools/install_mc5_autopatch.ps1` — установка хука в Python 3.7; `Tools/patch_mc5_ts4script.py` — ручной патч уже собранных `.ts4script`.
- Бинарные DLL не изменились с ru.1.

## Проверено

- Тесты автопатча на реальных сгенерированных MC5 скриптах (карьера и черта с ActionTrigger): 12/12.
- Работа исправленного скрипта в игре The Sims 4 1.129.39.1030: баг «Кто едет?» исчез, новых записей в `lastException.txt` нет.
- `verify-release.ps1`: RELEASE CHECK PASSED (2694 файла, 1280 XML без ошибок).

## Установка

1. Распакуйте ZIP в отдельную папку.
2. Запустите `Constructor5.exe`.
3. Для экспорта скриптов: установите Python 3.7 (в комплекте в `Python Installer\`) и выполните `Tools\install_mc5_autopatch.ps1`.
4. Откройте или создайте проект.

## Проверка

Сверьте SHA256 скачанного архива с суммой в описании релиза и в `checksums.sha256` внутри архива.
