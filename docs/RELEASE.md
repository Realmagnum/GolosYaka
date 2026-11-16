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

### Если сертификата Apple Developer нет

Нотаризация требует платного Apple Developer Program: без него подписать релиз так,
чтобы macOS открывала его без предупреждений, нельзя. Рабочий путь один — ad-hoc:

```bash
./build-release.sh --arch universal
```

Что получается и что это значит:

* `codesign --verify --strict --deep` проходит, приложение запускается на Apple Silicon
  (arm64 требует хоть какой-то подписи, ad-hoc её даёт);
* `spctl --assess` отклоняет бандл, у скачанного DMG остаётся `com.apple.quarantine`,
  поэтому пользователь снимает карантин вручную (инструкция в `INSTALL.txt` внутри DMG);
* ad-hoc подпись — это хеш бинарника, она меняется при каждой сборке. macOS привязывает
  TCC-разрешения к подписи, поэтому после обновления пользователь заново выдаёт
  «Универсальный доступ» (в приложении есть обработка этого состояния —
  `PermissionManager.isAccessibilityMismatch`);
* Keychain тоже может переспросить доступ к сохранённым API-ключам после обновления.

Если раздражает сброс разрешений при каждом релизе, можно один раз создать
самоподписанный сертификат и подписывать им: designated requirement тогда опирается на
сертификат, а не на хеш, и разрешения переживают обновления. Пользователю всё равно
нужно снять карантин, а сборку придётся подписывать на машине, где лежит этот сертификат:

```bash
# один раз, интерактивно (сертификат попадёт в login.keychain)
openssl req -x509 -newkey rsa:2048 -keyout /tmp/golosok.key -out /tmp/golosok.crt -days 3650 -nodes \
  -subj "/CN=Golosok Self-Signed/O=Realmagnum/C=RU" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"
openssl pkcs12 -export -inkey /tmp/golosok.key -in /tmp/golosok.crt -out /tmp/golosok.p12 -passout pass:golosok
security import /tmp/golosok.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P golosok -T /usr/bin/codesign
# дальше: ./build-release.sh --identity "Golosok Self-Signed"
```

Этот вариант не заменяет нотаризацию: предупреждение Gatekeeper остаётся, `spctl`
по-прежнему отклоняет бандл. Он лечит только повторную выдачу разрешений после обновлений.

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
Без сертификата этот шаг пропускается — см. «Если сертификата Apple Developer нет».

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
