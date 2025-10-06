# CRM n8n + Supabase

Автоматизированная CRM система для обработки email и управления сделками через Gmail, n8n и Supabase.

## Архитектура

```
Gmail (входящие письма)
    ↓
n8n Workflow 1: Email Processing
    ↓ (парсинг через OpenAI)
    ↓
Supabase (PostgreSQL + Functions)
    ↓
n8n Workflow 2: Daily Pings
    ↓
Gmail (уведомления пользователю)
```

## База данных

### Таблицы

**companies** - компании клиентов
- id (uuid, PK)
- name (text) - название компании
- domain (text) - домен сайта
- notes (text) - заметки
- created_at, updated_at (timestamptz)

**contacts** - контактные лица
- id (uuid, PK)
- company_id (uuid, FK → companies)
- email, first_name, last_name, phone, position (text)
- created_at, updated_at (timestamptz)

**pipeline_stages** - этапы воронки продаж
- id (int4, PK) - номер этапа 1-7
- name (text) - название этапа
- ping_interval (interval) - интервал для пинга
- ping_type (text) - тип пинга (auto/recurring)
- ping_action (text) - текст действия
- description (text)

**deals** - сделки
- id (uuid, PK)
- company_id (uuid, FK → companies)
- contact_id (uuid, FK → contacts)
- product_name (text) - название продукта
- product_description (text)
- price (numeric)
- stage (int4, FK → pipeline_stages) - текущий этап
- sample_shipment_date (date) - дата отгрузки образцов
- notes (text) - история общения
- status (varchar) - open/won/lost
- closed_at, created_at, updated_at (timestamptz)

**pings** - напоминания по сделкам
- id (uuid, PK)
- deal_id (uuid, FK → deals)
- ping_date (date) - дата напоминания
- type (text) - auto/manual/recurring
- action (text) - текст действия
- is_completed (bool)
- completed_at (timestamptz)
- notes (text)
- created_at (timestamptz)

### Полная схема

См. `docs/database-schema.sql` - содержит CREATE TABLE с PRIMARY KEY и FOREIGN KEY.

## Функции Supabase

Все функции в папке `supabase/*.sql`

### Основные функции

**process_email(p_data jsonb)** - точка входа для обработки писем
- Парсит данные от AI агента
- Создает/обновляет company → contact → deal
- Вызывает manage_pings() для управления напоминаниями
- Возвращает: deal_id, company_id, contact_id, stage, warnings, next_ping_date

**manage_pings(p_deal_id, p_new_stage, p_stage_changed, p_manual_ping_date, p_sample_shipment_date)**
- Закрывает старые пинги при смене этапа
- Создает новый пинг по правилам этапа
- Для этапов 3-5 использует sample_shipment_date для расчета
- Возвращает: pings_created, pings_closed, warnings, next_ping_date

**get_today_pings()** - возвращает таблицу пингов на сегодня
- Используется в Workflow 2 для ежедневных уведомлений
- Поля: ping_id, company_name, contact_name, product_name, stage, action, last_notes

**get_weekly_summary()** - сводка для пятницы
- overdue_pings - просроченные напоминания
- stuck_deals - сделки без движения >2 недель
- pipeline_stats - статистика по этапам

### Вспомогательные функции

**upsert_company(p_name)** - создание/поиск компании
- Нормализует название (убирает ООО, АО, кавычки)
- Ищет по нормализованному имени
- Возвращает company_id

**upsert_contact(p_email, p_first_name, p_last_name, p_phone, p_company_id)**
- Ищет по email, затем по ФИО+компания
- Обновляет существующий или создает новый
- Возвращает contact_id

**upsert_deal(p_company_id, p_contact_id, p_product_name, ...)**
- Ищет открытую сделку по company_id + product_name
- Обновляет существующую или создает новую
- Возвращает: deal_id, stage_changed, old_stage, new_stage

**close_deal(p_deal_id, p_status, p_close_reason)**
- Закрывает сделку со статусом won/lost
- Закрывает все активные пинги
- Добавляет запись в notes
- Возвращает: success, deal_id, status, company_name, product_name

**reopen_deal(p_deal_id, p_reason)**
- Переоткрывает закрытую сделку
- Добавляет причину в notes

**mark_ping_completed(p_ping_id, p_notes)**
- Помечает пинг выполненным
- Возвращает boolean

**get_deals_statistics()**
- Общая статистика: total_deals, open_deals, won_deals, lost_deals, win_rate, total_revenue

**update_updated_at_column()** - триггер для автообновления updated_at

## Workflow 1: Email Processing

**Файл:** `workflows/email-processing.json`

**Триггер:** Gmail Trigger - каждую минуту проверяет UNREAD письма (исключая requestled@gmail.com)

**Логика:**

1. **Code** - парсит письмо:
   - Очищает subject от RE:/FW:
   - Проверяет команды закрытия (won/lost в начале текста)
   
2. **If** - проверяет isCloseCommand:

   **TRUE (закрытие сделки):**
   - Find Deal for Close - ищет открытую сделку по product_name
   - Check Deal Found - проверяет что нашли
   - Close Deal in DB - вызывает close_deal()
   - Send Close Success - отправляет HTML уведомление
   
   **FALSE (обработка сделки):**
   - Check Existing Deal - ищет сделку по product_name
   - Parse Email with AI - OpenAI GPT-4 парсит письмо:
     - Извлекает: company_name, contact (email/phone/name), stage, dates, notes
     - Игнорирует данные Symmetron/Болотяна
     - Читает служебные пометки в начале письма
   - Parse JSON from AI - обрабатывает ответ AI, мерджит с existing_deal
   - Process Email in Supabase - вызывает process_email()
   - Get Names from DB - получает актуальные данные
   - Send Warning Email - отправляет HTML подтверждение
   - Mark as read - помечает письмо прочитанным

**Промпт для AI:**
- Извлекает данные КЛИЕНТА (не Symmetron)
- Определяет stage (1-7) по содержанию или из пометки "Этап X"
- Парсит телефоны из служебных пометок
- Возвращает чистый JSON без markdown

## Workflow 2: Daily Pings

**Файл:** `workflows/daily-pings.json`

**Триггер:** Schedule - каждый будний день в 9:00

**Логика:**

1. **Check if Friday** - определяет день недели
2. **Store Friday Data** - сохраняет флаг isFriday
3. **Get Today Pings** - получает пинги на сегодня
4. **Loop Over Pings** - для каждого пинга:
   - Format Single Ping - создает HTML письмо с карточкой
   - Send Ping Email - отправляет на evgeniy.bolotian@symmetron.ru
5. **IF Friday After Loop** - если пятница:
   - Get Weekly Summary - вызывает get_weekly_summary()
   - Format Weekly Summary - создает HTML с статистикой
   - Send Weekly Summary - отправляет сводку

**HTML формат:**
- Карточка пинга: компания, этап, контакт, действие, последние заметки
- Сводка: просроченные пинги, застрявшие сделки, статистика по воронке

## Этапы воронки (pipeline_stages)

1. **Выявление потребности** - интервал 14 дней
2. **Обработка запроса/КП** - интервал 7 дней
3. **Поставка образцов** - пинг сегодня (требует sample_shipment_date)
4. **Подтверждение получения** - пинг через 14 дней от отгрузки
5. **Результат тестирования** - пинг через 30 дней от отгрузки
6. **Получение заказа** - интервал 7 дней
7. **Повторные заказы** - recurring, интервал 30 дней

## Взаимодействие через Gmail

**Входящие письма:**
- Subject = product_name (название сделки)
- Служебные пометки в начале тела письма:
  ```
  Этап 3
  Компания Витрулюкс
  +7 (993) 205-13-94
  ```
- Команды закрытия в начале тела:
  ```
  won: Подписали контракт на 500к
  lost: Выбрали конкурента
  ```

**Исходящие уведомления:**
- Подтверждение обработки письма (компания, контакт, сделка, этап, даты)
- Ежедневные пинги по каждой сделке
- Пятничная сводка (просрочки, застрявшие сделки, статистика)

## Структура проекта

```
/
├── workflows/
│   ├── email-processing.json    # Workflow 1
│   └── daily-pings.json         # Workflow 2
├── supabase/
│   ├── close_deal.sql
│   ├── get_deals_statistics.sql
│   ├── get_today_pings.sql
│   ├── get_weekly_summary.sql
│   ├── manage_pings.sql
│   ├── mark_ping_completed.sql
│   ├── process_email.sql
│   ├── reopen_deal.sql
│   ├── update_updated_at_column.sql
│   ├── upsert_company.sql
│   ├── upsert_contact.sql
│   └── upsert_deal.sql
├── docs/
│   └── database-schema.sql      # Полная схема БД
├── README.md
└── PROJECT.md                   # Этот файл
```

## Для разработки

**Репозиторий:** https://github.com/Florosonic/crm-n8n-supabase

**Технологии:**
- n8n (self-hosted или cloud)
- Supabase (PostgreSQL + Functions)
- OpenAI API (GPT-4 для парсинга email)
- Gmail API

**Развертывание:**
1. Импортировать workflows в n8n
2. Настроить credentials (Gmail OAuth, Supabase, OpenAI)
3. Выполнить `docs/database-schema.sql` в Supabase
4. Выполнить все функции из `supabase/*.sql`
5. Заполнить `pipeline_stages` данными (1-7 этапов)