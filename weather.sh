#!/usr/bin/env bash

# Включаем строгий режим:
# -e  выход при ошибке любой команды (кроме как в условиях)
# -u  ошибка при использовании неопределённой переменной
# -o pipefail  ошибка, если любая команда в конвейере завершилась неудачно
set -euo pipefail

# Первый аргумент скрипта — город, второй (опционально) — путь к файлу HTML
CITY="${1:-}"
OUT_FILE="${2:-/var/www/html/index.html}"

# Если город не указан — выводим подсказку и завершаем работу с ошибкой
if [ -z "$CITY" ]; then
    echo "Ошибка: необходимо указать город"
    echo "Пример: $0 Perm"
    exit 1
fi

# Кодируем название города для безопасного использования в URL (например, пробелы и кириллица)
CITY_ENCODED=$(printf '%s' "$CITY" | jq -sRr @uri)

# Формируем URL к API wttr.in (формат JSON)
URL="https://wttr.in/${CITY_ENCODED}?format=j1"

# Загружаем JSON с погодой, ограничивая время ожидания 20 секундами
JSON=$(curl -fsSL --max-time 20 "$URL")

# Извлекаем нужные поля из JSON с помощью jq:
# температура в Цельсиях, влажность, ощущается как, текстовое описание погоды
TEMP_C=$(echo "$JSON" | jq -r '.current_condition[0].temp_C')
HUMIDITY=$(echo "$JSON" | jq -r '.current_condition[0].humidity')
FEELS_LIKE=$(echo "$JSON" | jq -r '.current_condition[0].FeelsLikeC')
DESCRIPTION=$(echo "$JSON" | jq -r '.current_condition[0].weatherDesc[0].value')

# Запоминаем текущую дату и время для отображения в таблице
UPDATED_AT=$(date '+%Y-%m-%d %H:%M:%S')

# Кодируем город и описание для безопасной вставки в HTML (защита от XSS)
HTML_CITY=$(printf '%s' "$CITY" | jq -Rr @html)
HTML_DESCRIPTION=$(printf '%s' "$DESCRIPTION" | jq -Rr @html)

# Извлекаем директорию, где должен лежать итоговый HTML-файл, и создаём её при необходимости
OUT_DIR=$(dirname "$OUT_FILE")
mkdir -p "$OUT_DIR"

# Если файла не существует или в нём нет закрывающего тега </tbody> (значит, структура нарушена) —
# создаём новый HTML-файл с «шапкой» и пустой таблицей.
if [ ! -f "$OUT_FILE" ] || ! grep -q '</tbody>' "$OUT_FILE"; then
cat > "$OUT_FILE" <<HTML
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Журнал погоды</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: #f2f4f8;
            color: #222;
            margin: 40px;
        }
        h1 {
            color: #1f5fbf;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            background: white;
            box-shadow: 0 4px 14px rgba(0,0,0,0.12);
        }
        th, td {
            border: 1px solid #ddd;
            padding: 10px;
            text-align: center;
        }
        th {
            background: #1f5fbf;
            color: white;
        }
        tr:nth-child(even) {
            background: #f7f7f7;
        }
    </style>
</head>
<body>
    <h1>Журнал погоды</h1>
    <table>
        <thead>
            <tr>
                <th>Дата и время</th>
                <th>Город</th>
                <th>Температура</th>
                <th>Ощущается как</th>
                <th>Влажность</th>
                <th>Описание</th>
            </tr>
        </thead>
        <tbody>
        </tbody>
    </table>
</body>
</html>
HTML
fi

# Создаём временный файл в той же директории, чтобы атомарно заменить исходный
TMP_FILE=$(mktemp "${OUT_DIR}/.weather.XXXXXX")

# Формируем новое содержимое HTML:
# - все строки из старого файла до строки, содержащей '</tbody>', включая её саму (удаляем всё после)
# - вставляем новую строку таблицы с данными о погоде
# - затем закрывающие теги </tbody>, </table>, </body>, </html>
{
    # Выводим всё из старого файла, но удаляем строки от '</tbody>' до конца файла.
    sed '/<\/tbody>/,$d' "$OUT_FILE"

    # Вставляем новую запись
    cat <<HTML
            <tr>
                <td>${UPDATED_AT}</td>
                <td>${HTML_CITY}</td>
                <td>${TEMP_C} °C</td>
                <td>${FEELS_LIKE} °C</td>
                <td>${HUMIDITY}%</td>
                <td>${HTML_DESCRIPTION}</td>
            </tr>
        </tbody>
    </table>
</body>
</html>
HTML
} > "$TMP_FILE"

# Устанавливаем корректные права (владелец может читать/писать, остальные — только читать)
chmod 644 "$TMP_FILE"
# Заменяем старый файл новым
mv "$TMP_FILE" "$OUT_FILE"

# Выводим короткое сообщение в консоль о том, что данные добавлены
echo "Данные добавлены: ${UPDATED_AT}, ${CITY}, ${TEMP_C} °C, влажность ${HUMIDITY}%"
