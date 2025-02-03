#!/bin/zsh

# ---- Определяем, где лежит brew ----
if command -v brew &>/dev/null; then
    BREW="$(command -v brew)"
elif [ -x "/opt/homebrew/bin/brew" ]; then
    BREW="/opt/homebrew/bin/brew"
elif [ -x "/usr/local/bin/brew" ]; then
    BREW="/usr/local/bin/brew"
else
    echo "[ERROR] Homebrew не найден. Установите brew или проверьте PATH."
    exit 1
fi

# ---- Получаем список всех cask-приложений и их .app ----
echo "[INFO] Считываем информацию о cask-приложениях..."
all_casks_installed=$($BREW list --cask 2>/dev/null)
if [ -z "$all_casks_installed" ]; then
    echo "[WARNING] Похоже, что через brew cask ничего не установлено, или brew cask не поддерживается."
    all_casks_installed=""
fi

if [ -n "$all_casks_installed" ]; then
    # Сразу собираем всю JSON-информацию
    all_casks_info=$($BREW info --cask --json=v2 $all_casks_installed 2>/dev/null)
fi

# Создадим ассоциативный массив (bash 4+) "ИмяApp -> cask-токен"
declare -A cask_map

if [ -n "$all_casks_info" ]; then
    # Пробегаем все cask-формулы, вытаскиваем .app
    # Используем jq для парсинга JSON (нужен установленный jq).
    # Если jq нет — можно в теории сделать grep/sed, но гораздо сложнее.
    if command -v jq &>/dev/null; then
        cask_count=$(echo "$all_casks_info" | jq '.casks | length')
        for i in $(seq 0 $((cask_count - 1))); do
            cask_token=$(echo "$all_casks_info" | jq -r ".casks[$i].token")
            # Список app, которые декларирует данный cask
            app_paths=$(echo "$all_casks_info" \
                | jq -r ".casks[$i].artifacts[]? | select(type==\"string\" and endswith(\".app\"))")

            # Если cask раскладывает несколько .app, нам нужно учесть все
            for a_path in $app_paths; do
                base_app_name="$(basename "$a_path")"  # например, Telegram.app
                cask_map["$base_app_name"]="$cask_token"
            done
        done
    else
        echo "[WARNING] jq не установлен, не могу распарсить brew cask JSON. Продолжаем без точного сопоставления."
    fi
fi

# ---- Собираем список всех приложений (best effort) ----
declare -a apps_dirs=(
    "/Applications"
    "/System/Applications"
    "/Library/Applications"
    "$HOME/Applications"
)

declare -a found_apps=()

for dir in "${apps_dirs[@]}"; do
    # Ищем .app только на один уровень глубины
    if [ -d "$dir" ]; then
        # shellcheck disable=SC2044
        for app in "$dir"/*.app "$dir"/*/*.app; do
            # Проверяем, что файл/директория реально существует
            [ -e "$app" ] || continue
            found_apps+=("$app")
        done
    fi
done

# ---- Выводим заголовок ----
echo "------------------------------------------------------------------"
echo " Список приложений и источник (Brew Cask / Mac App Store / ...)"
echo "------------------------------------------------------------------"

# ---- Проходим по каждому найденному приложению ----
for app_path in "${found_apps[@]}"; do
    app_name="$(basename "$app_path" .app)"     # Без .app
    base_app="$(basename "$app_path")"          # C .app
    is_brew="No"
    cask_name=""

    # Проверяем в cask_map
    if [ -n "${cask_map["$base_app"]}" ]; then
        is_brew="Yes"
        cask_name="(${cask_map["$base_app"]})"
    fi

    # Проверяем наличие App Store чека
    appstore_receipt="$(mdls -raw -name kMDItemAppStoreHasReceipt "$app_path" 2>/dev/null)"
    # У некоторых приложений mdls выдаст "1", у некоторых "0" или "kMDItemNotFound"
    # Иногда бывает true/false. Зависит от версии ОС.
    # Проверим сразу и "1", и "true":
    if [[ "$appstore_receipt" == "1" || "$appstore_receipt" == "true" ]]; then
        appstore="(App Store)"
    else
        appstore=""
    fi

    # Итоговая строка
    echo "- $app_name: Brew=$is_brew $cask_name $appstore — $app_path"
done

echo "------------------------------------------------------------------"