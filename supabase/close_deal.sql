CREATE OR REPLACE FUNCTION public.close_deal(p_deal_id uuid, p_status character varying, p_close_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_old_status VARCHAR(20);
    v_old_stage INTEGER;
    v_company_name TEXT;
    v_product_name TEXT;
BEGIN
    -- Проверяем валидность статуса
    IF p_status NOT IN ('won', 'lost') THEN
        RAISE EXCEPTION 'Статус должен быть won или lost';
    END IF;
    
    -- Получаем текущую информацию о сделке
    SELECT d.status, d.stage, c.name, d.product_name
    INTO v_old_status, v_old_stage, v_company_name, v_product_name
    FROM deals d
    JOIN companies c ON c.id = d.company_id
    WHERE d.id = p_deal_id;
    
    -- Проверяем существование сделки
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Сделка не найдена: %', p_deal_id;
    END IF;
    
    -- Проверяем, не закрыта ли уже сделка
    IF v_old_status != 'open' THEN
        RAISE EXCEPTION 'Сделка уже закрыта со статусом: %', v_old_status;
    END IF;
    
    -- Обновляем сделку
    UPDATE deals
    SET 
        status = p_status,
        closed_at = NOW(),
        notes = CASE 
            WHEN p_close_reason IS NOT NULL THEN 
                COALESCE(notes || E'\n---\n' || TO_CHAR(NOW(), 'DD.MM.YYYY HH24:MI') || 
                E'\nСделка закрыта (' || p_status || '): ' || p_close_reason, p_close_reason)
            ELSE notes
        END,
        updated_at = NOW()
    WHERE id = p_deal_id;
    
    -- Закрываем все активные пинги для этой сделки
    UPDATE pings
    SET is_completed = TRUE, completed_at = NOW()
    WHERE deal_id = p_deal_id AND is_completed = FALSE;
    
    RETURN jsonb_build_object(
        'success', TRUE,
        'deal_id', p_deal_id,
        'status', p_status,
        'company_name', v_company_name,
        'product_name', v_product_name,
        'old_stage', v_old_stage,
        'closed_at', NOW()
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', SQLERRM
        );
END;
$function$
