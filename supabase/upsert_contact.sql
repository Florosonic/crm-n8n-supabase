CREATE OR REPLACE FUNCTION public.upsert_contact(p_email text, p_first_name text, p_last_name text, p_phone text, p_company_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_contact_id UUID;
    v_normalized_email TEXT;
BEGIN
    -- Нормализация email
    v_normalized_email := LOWER(TRIM(p_email));
    
    -- Сначала ищем по email, если указан
    IF v_normalized_email IS NOT NULL AND v_normalized_email != '' THEN
        SELECT id INTO v_contact_id
        FROM contacts
        WHERE LOWER(email) = v_normalized_email;
        
        -- Если нашли по email - обновляем ФИО и компанию если нужно
        IF v_contact_id IS NOT NULL THEN
            UPDATE contacts
            SET first_name = COALESCE(p_first_name, first_name),
                last_name = COALESCE(p_last_name, last_name),
                phone = COALESCE(p_phone, phone),
                company_id = COALESCE(p_company_id, company_id),
                updated_at = NOW()
            WHERE id = v_contact_id;
            RETURN v_contact_id;
        END IF;
    END IF;
    
    -- Если не нашли по email - ищем по ФИО + компания
    IF p_first_name IS NOT NULL OR p_last_name IS NOT NULL THEN
        SELECT id INTO v_contact_id
        FROM contacts
        WHERE company_id = p_company_id
          AND LOWER(COALESCE(first_name, '')) = LOWER(COALESCE(p_first_name, ''))
          AND LOWER(COALESCE(last_name, '')) = LOWER(COALESCE(p_last_name, ''));
        
        -- Если нашли по ФИО - обновляем email
        IF v_contact_id IS NOT NULL THEN
            UPDATE contacts
            SET email = COALESCE(v_normalized_email, email),
                phone = COALESCE(p_phone, phone),
                updated_at = NOW()
            WHERE id = v_contact_id;
            RETURN v_contact_id;
        END IF;
    END IF;
    
    -- Если никого не нашли - создаем нового
    INSERT INTO contacts (company_id, email, first_name, last_name, phone)
    VALUES (p_company_id, v_normalized_email, p_first_name, p_last_name, p_phone)
    RETURNING id INTO v_contact_id;
    
    RETURN v_contact_id;
END;
$function$
