#!/bin/zsh

# Папка для "мусора"
TRASH="$HOME/.trash"
mkdir -p "$TRASH"

echo "\n📦 Перемещение следов 'kasper' в $TRASH\n"

# Поиск и обработка всех путей, где есть 'kasper'
sudo find / -iname '*kpm*' -print0 2>/dev/null | while IFS= read -r -d '' path; do
    echo "\n🔎 Найдено: \"$path\""
    read "answer?Переместить в корзину? (y/n): "

    if [[ "$answer" == "y" ]]; then
        dest="$TRASH${path}"
        dest_dir=$(dirname "$dest")

        echo "📁 Создаю структуру: \"$dest_dir\""
        sudo mkdir -p "$dest_dir"

        echo "🚚 Перемещаю → \"$dest\""
        sudo mv "$path" "$dest"
    else
        echo "⏭ Пропущено"
    fi
done

echo "\n✅ Готово. Всё перенесено в ~/.trash (с подтверждением)"