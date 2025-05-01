#!/bin/zsh

echo "🔐 Apple Pay Fix Script — Проверка системных настроек безопасности"
echo "--------------------------------------------------------------"

# 1. Включаем автоматические обновления macOS
echo "🛠️ Включаем автоматические обновления..."
sudo softwareupdate --schedule on

# 2. Включаем автоматическую установку security updates через defaults
echo "🔧 Настройка system preferences..."
sudo /usr/bin/defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool true
sudo /usr/bin/defaults write /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall -bool true
sudo /usr/bin/defaults write /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall -bool true
sudo /usr/bin/defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true

# 3. Проверка текущих значений
echo "🔍 Проверка настроек (текущее состояние):"
echo "AutomaticallyInstallMacOSUpdates: $(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates)"
echo "CriticalUpdateInstall:            $(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate CriticalUpdateInstall)"
echo "ConfigDataInstall:                $(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate ConfigDataInstall)"
echo "App Store AutoUpdate:             $(/usr/bin/defaults read /Library/Preferences/com.apple.commerce AutoUpdate)"

# 4. Проверка SIP
echo ""
echo "🔐 Проверка SIP (System Integrity Protection)..."
SIP_STATUS=$(csrutil status 2>&1)

if [[ "$SIP_STATUS" == *"enabled"* ]]; then
    echo "✅ SIP включен — всё хорошо."
else
    echo "❌ SIP выключен. Apple Pay не будет работать!"
    echo "📌 Чтобы включить SIP:"
    echo "   1. Перезагрузите Mac в Recovery Mode (⌘ + R при запуске)"
    echo "   2. Откройте Terminal из меню 'Utilities'"
    echo "   3. Введите: csrutil enable"
    echo "   4. Перезагрузитесь"
fi

echo ""
echo "🔁 Перезагрузите Mac, чтобы изменения вступили в силу."
echo "💳 После перезагрузки проверьте работу Apple Pay в System Settings > Wallet & Apple Pay."