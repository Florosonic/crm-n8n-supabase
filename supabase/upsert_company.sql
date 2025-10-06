CREATE OR REPLACE FUNCTION public.upsert_company(p_name text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_normalized_name TEXT;
    v_company_id UUID;
BEGIN
    -- Нормализация названия: убираем ООО, АО, кавычки, лишние пробелы
    v_normalized_name := TRIM(p_name);
    v_normalized_name := REGEXP_REPLACE(v_normalized_name, '^(ООО|ОАО|ЗАО|АО|ИП|ПАО)\s+', '', 'i');
    v_normalized_name := REGEXP_REPLACE(v_normalized_name, '[«»"''"]', '', 'g');
    v_normalized_name := TRIM(v_normalized_name);
    
    -- Проверка на пустое название
    IF v_normalized_name = '' OR v_normalized_name IS NULL THEN
        v_normalized_name := 'Компания ' || TO_CHAR(NOW(), 'DD.MM.YYYY');
    END IF;
    
    -- Поиск существующей компании
    SELECT id INTO v_company_id
    FROM companies
    WHERE LOWER(REGEXP_REPLACE(REGEXP_REPLACE(name, '^(ООО|ОАО|ЗАО|АО|ИП|ПАО)\s+', '', 'i'), '[«»"''"]', '', 'g')) 
          = LOWER(v_normalized_name);
    
    -- Если не нашли - создаем новую
    IF v_company_id IS NULL THEN
        INSERT INTO companies (name, notes)
        VALUES (v_normalized_name, 'Создано автоматически из email')
        RETURNING id INTO v_company_id;
    END IF;
    
    RETURN v_company_id;
END;
$function$
