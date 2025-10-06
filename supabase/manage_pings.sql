CREATE OR REPLACE FUNCTION public.manage_pings(p_deal_id uuid, p_new_stage integer, p_stage_changed boolean, p_manual_ping_date date, p_sample_shipment_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_ping_interval INTERVAL;
    v_ping_type TEXT;
    v_ping_action TEXT;
    v_ping_date DATE;
    v_pings_created INTEGER := 0;
    v_pings_closed INTEGER := 0;
    v_warnings TEXT[] := ARRAY[]::TEXT[];
    v_next_ping_date DATE := NULL;
BEGIN
    IF p_manual_ping_date IS NOT NULL THEN
        UPDATE pings
        SET is_completed = TRUE,
            completed_at = NOW(),
            notes = 'Заменен ручным пингом'
        WHERE deal_id = p_deal_id
          AND type IN ('auto', 'manual', 'recurring')
          AND is_completed = FALSE;
        
        GET DIAGNOSTICS v_pings_closed = ROW_COUNT;
        
        INSERT INTO pings (deal_id, ping_date, type, action)
        VALUES (p_deal_id, p_manual_ping_date, 'manual', 'Выполнить запланированное действие');
        
        v_pings_created := 1;
        v_next_ping_date := p_manual_ping_date;
        
        RETURN jsonb_build_object(
            'pings_created', v_pings_created,
            'pings_closed', v_pings_closed,
            'warnings', v_warnings,
            'next_ping_date', v_next_ping_date
        );
    END IF;
    
    IF p_stage_changed THEN
        UPDATE pings
        SET is_completed = TRUE,
            completed_at = NOW(),
            notes = 'Закрыто при смене этапа'
        WHERE deal_id = p_deal_id
          AND type IN ('auto', 'recurring')
          AND is_completed = FALSE;
        
        GET DIAGNOSTICS v_pings_closed = ROW_COUNT;
        
        SELECT ping_interval, ping_type, ping_action
        INTO v_ping_interval, v_ping_type, v_ping_action
        FROM pipeline_stages
        WHERE id = p_new_stage;
        
        IF p_new_stage IN (3, 4, 5) THEN
            IF p_sample_shipment_date IS NOT NULL THEN
                IF p_new_stage = 3 THEN
                    v_ping_date := CURRENT_DATE;
                ELSIF p_new_stage = 4 THEN
                    v_ping_date := p_sample_shipment_date + INTERVAL '14 days';
                ELSIF p_new_stage = 5 THEN
                    v_ping_date := p_sample_shipment_date + INTERVAL '30 days';
                END IF;
            ELSE
                v_ping_date := CURRENT_DATE;
                IF p_new_stage = 3 THEN
                    v_ping_action := 'Уточнить дату отгрузки образцов';
                END IF;
                v_warnings := array_append(v_warnings, 'Для этапа ' || p_new_stage || ' рекомендуется указать дату отгрузки');
            END IF;
        ELSE
            v_ping_date := CURRENT_DATE + v_ping_interval;
        END IF;
        
        -- Проверка: если пинг в прошлом, ставим через 14 дней от сегодня
        IF v_ping_date < CURRENT_DATE THEN
            v_ping_date := CURRENT_DATE + INTERVAL '14 days';
        END IF;
        
        IF v_ping_type = 'recurring' THEN
            INSERT INTO pings (deal_id, ping_date, type, action)
            VALUES (p_deal_id, v_ping_date, 'recurring', v_ping_action);
        ELSE
            INSERT INTO pings (deal_id, ping_date, type, action)
            VALUES (p_deal_id, v_ping_date, 'auto', v_ping_action);
        END IF;
        
        v_pings_created := v_pings_created + 1;
        v_next_ping_date := v_ping_date;
    END IF;
    
    UPDATE pings
    SET is_completed = TRUE,
        completed_at = NOW(),
        notes = 'Автоматически закрыто при обновлении сделки'
    WHERE deal_id = p_deal_id
      AND ping_date < CURRENT_DATE
      AND is_completed = FALSE;
    
    RETURN jsonb_build_object(
        'pings_created', v_pings_created,
        'pings_closed', v_pings_closed,
        'warnings', v_warnings,
        'next_ping_date', v_next_ping_date
    );
END;
$function$
