# GolosYaka 1.21.0

## Русский

### Что улучшено
- **Отдельный список моделей для каждого AI-провайдера:** при переключении провайдера больше не отображаются модели другого сервиса. Загруженные списки сохраняются между запусками.
- **Понятная индикация загрузки:** в поле выбора модели показываются индикатор и подпись загрузки. Если открыть список во время обновления, он появится автоматически после завершения.
- **Миграция старых аудиозаписей — только когда она нужна:** опция сжатия архива показывается, только если от ранних версий приложения остались WAV-файлы без копии в AAC. Для новых установок и уже перенесённых архивов раздел скрыт.

### Исправления
- Поздний ответ на запрос моделей предыдущего провайдера больше не подменяет список текущего.
- Состояния загрузки и ошибки получения моделей изолированы для выбранного провайдера.

## English

### What's improved
- **Provider-specific model lists:** each AI provider now keeps its own model list, so switching providers no longer shows another provider's models. Loaded lists are remembered between launches.
- **Clear feedback while models load:** the model picker shows a progress indicator and loading label. If you open the list during a refresh, it appears automatically when loading finishes.
- **Legacy audio migration, only when needed:** the archive-compression option is shown only when recordings from earlier versions remain in WAV format without an AAC copy. New installations and already-migrated archives stay uncluttered.

### Fixes
- Prevented a late response from an old provider's model request from replacing the currently selected provider's list.
- Improved feedback and error-state isolation when fetching models for different providers.
