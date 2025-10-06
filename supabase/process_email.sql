CREATE OR REPLACE FUNCTION public.process_email(p_data jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_company_id UUID;
    v_contact_id UUID;
    v_deal_result JSONB;
    v_ping_result JSONB;
    v_warnings TEXT[] := ARRAY[]::TEXT[];
    v_confidence NUMERIC;
BEGIN
    -- Извлекаем уверенность AI
    v_confidence := COALESCE((p_data->>'confidence')::NUMERIC, 1.0);
    
    -- Если низкая уверенность - добавляем предупреждение
    IF v_confidence < 0.7 THEN
        v_warnings := array_append(v_warnings, 
            'Низкая уверенность AI в парсинге: ' || (v_confidence * 100)::INTEGER || '%');
    END IF;
    
    -- НОВОЕ: Проверяем existing_deal_id
    IF (p_data->>'existing_deal_id') IS NOT NULL THEN
        -- Получаем company_id из существующей сделки
        SELECT company_id, contact_id 
        INTO v_company_id, v_contact_id
        FROM deals 
        WHERE id = (p_data->>'existing_deal_id')::UUID;
        
        -- Обновляем контакт если передан
        IF (p_data->>'contact_email') IS NOT NULL OR 
           (p_data->>'contact_first_name') IS NOT NULL OR 
           (p_data->>'contact_last_name') IS NOT NULL THEN
            v_contact_id := upsert_contact(
                p_data->>'contact_email',
                p_data->>'contact_first_name',
                p_data->>'contact_last_name',
                p_data->>'contact_phone',
                v_company_id
            );
        END IF;
    ELSE
        -- Старая логика для новых сделок
        -- 1. Обрабатываем компанию
        v_company_id := upsert_company(p_data->>'company_name');
        
        -- 2. Обрабатываем контакт (если указан)
        IF (p_data->>'contact_email') IS NOT NULL OR 
           (p_data->>'contact_first_name') IS NOT NULL OR 
           (p_data->>'contact_last_name') IS NOT NULL THEN
            v_contact_id := upsert_contact(
                p_data->>'contact_email',
                p_data->>'contact_first_name',
                p_data->>'contact_last_name',
                p_data->>'contact_phone',
                v_company_id
            );
        END IF;
    END IF;
    
    -- 3. Обрабатываем сделку
    v_deal_result := upsert_deal(
        v_company_id,
        v_contact_id,
        p_data->>'product_name',
        p_data->>'product_description',
        (p_data->>'price')::DECIMAL,
        COALESCE((p_data->>'stage')::INTEGER, 1),
        (p_data->>'sample_shipment_date')::DATE,
        p_data->>'notes'
    );
    
    -- 4. Управляем пингами
    v_ping_result := manage_pings(
        (v_deal_result->>'deal_id')::UUID,
        COALESCE((p_data->>'stage')::INTEGER, 1),
        (v_deal_result->>'stage_changed')::BOOLEAN,
        (p_data->>'manual_ping_date')::DATE,
        (p_data->>'sample_shipment_date')::DATE
    );
    
    -- Объединяем предупреждения
    IF jsonb_array_length(v_ping_result->'warnings') > 0 THEN
        v_warnings := v_warnings || ARRAY(
            SELECT jsonb_array_elements_text(v_ping_result->'warnings')
        );
    END IF;
    
    -- Формируем ответ
    RETURN jsonb_build_object(
        'success', TRUE,
        'deal_id', v_deal_result->>'deal_id',
        'company_id', v_company_id,
        'contact_id', v_contact_id,
        'stage', COALESCE((p_data->>'stage')::INTEGER, 1),
        'stage_changed', v_deal_result->>'stage_changed',
        'pings_created', v_ping_result->>'pings_created',
        'pings_closed', v_ping_result->>'pings_closed',
        'has_warnings', (array_length(v_warnings, 1) > 0),
        'warnings', v_warnings,
        'next_ping_date', v_ping_result->>'next_ping_date'  -- НОВОЕ: добавляем дату пинга
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', SQLERRM,
            'has_warnings', TRUE,
            'warnings', ARRAY['Критическая ошибка: ' || SQLERRM]
        );
END;
$function$
