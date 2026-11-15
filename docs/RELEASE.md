# Release Checklist — Golosok

Единый источник версии — файл `VERSION` (`1.14.0`). Из него берут версию
`build-dev.sh`, `build-release.sh`, шаблон `Info.plist` и Xcode (`MARKETING_VERSION`).
Расхождение версий ловит `scripts/verify_project_invariants.py` — сборка упадёт.

## 1. Подготовка версии

```bash
# bump: VERSION + pbxproj MARKETING_VERSION (оба — до одного значения)
echo 1.14.0 > VERSION
# в Golosok.xcodeproj/project.pbxproj: MARKETING_VERSION = 1.14.0;
python3 scripts/verify_project_invariants.py
```

`CFBundleVersion` (build) вычисляется из `git rev-list --count HEAD` — руками не правится.

## 2. Прогон проверок

```bash
./scripts/run-tests.sh          # smoke-набор без Xcode; с Xcode — полный test-таргет
./build-dev.sh                  # invariant gate + universal dev-бандл
```

## 3. Ресурсы внутри бандла

Релиз обязан содержать **реальные файлы**, без симлинков на `/Applications`:

```bash
GOLOSOK_RESOURCES_DIR=/Applications/Golosok.app/Contents/Resources \
  ./build-release.sh --arch universal
```

Каталог ресурсов должен содержать: `ffmpeg`, `whisper-cli`, `transcribe-cli`,
`gigaam.gguf`, `AppIcon.icns`, `Assets.car`. Скрипт копирует их через
`rsync --copy-links` и падает, если в бандле остался хоть один симлинк
(`codesign --verify` на таких бандлах даёт
`invalid destination for symbolic link in bundle`).

## 4. Подпись

```bash
# репозиторий сертификатов: Developer ID Application в связке ключей
./build-release.sh --identity "Developer ID Application: Name (TEAMID)"
```

Скрипт:

1. подписывает `ffmpeg`, `whisper-cli`, `transcribe-cli` (вложенные Mach-O);
2. подписывает `.app` с `--options runtime` и `Golosok.entitlements`
   (`com.apple.security.device.audio-input`, network client, user-selected files);
3. проверяет `codesign --verify --strict --deep`.

Без сертификата скрипт делает ad-hoc подпись и печатает инструкцию для пользователей:

```
xattr -cr /Applications/Golosok.app
```

Ad-hoc DMG нельзя нотаризовать — Gatekeeper покажет предупреждение.

## 5. Нотаризация

Один раз сохранить креды:

```bash
xcrun notarytool store-credentials golosok \
  --apple-id "you@example.com" --team-id TEAMID --password "app-specific-password"
```

Затем:

```bash
./build-release.sh \
  --identity "Developer ID Application: Name (TEAMID)" \
  --notary-profile golosok
```

Скрипт отправит DMG в notarytool, дождётся результата и сделает `stapler staple`.

## 6. Артефакты

```
dist/Golosok-1.14.0.dmg
dist/Golosok-1.14.0.dmg.sha256
```

Проверка на чистой машине:

```bash
codesign --verify --strict --deep /Applications/Golosok.app
spctl --assess --type execute --verbose=4 /Applications/Golosok.app
```

## 7. Что публикуется вместе с релизом

* `THIRD-PARTY-NOTICES.md` — копируется внутрь бандла (`Contents/Resources`).
* `LICENSE.md` — копируется внутрь бандла.
* Апдейтер приложения смотрит только на `Realmagnum/Golosok` и принимает только
  HTTPS-ассеты `github.com` / `objects.githubusercontent.com`
  (`AudioCapture.isTrustedReleaseAsset`), поэтому чужой DMG не подхватится.
