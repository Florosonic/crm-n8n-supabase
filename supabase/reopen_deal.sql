CREATE OR REPLACE FUNCTION public.reopen_deal(p_deal_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_old_status VARCHAR(20);
    v_company_name TEXT;
    v_product_name TEXT;
BEGIN
    -- Получаем текущую информацию о сделке
    SELECT d.status, c.name, d.product_name
    INTO v_old_status, v_company_name, v_product_name
    FROM deals d
    JOIN companies c ON c.id = d.company_id
    WHERE d.id = p_deal_id;
    
    -- Проверяем существование сделки
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Сделка не найдена: %', p_deal_id;
    END IF;
    
    -- Проверяем, закрыта ли сделка
    IF v_old_status = 'open' THEN
        RAISE EXCEPTION 'Сделка уже открыта';
    END IF;
    
    -- Переоткрываем сделку
    UPDATE deals
    SET 
        status = 'open',
        closed_at = NULL,
        notes = CASE 
            WHEN p_reason IS NOT NULL THEN 
                COALESCE(notes || E'\n---\n' || TO_CHAR(NOW(), 'DD.MM.YYYY HH24:MI') || 
                E'\nСделка переоткрыта: ' || p_reason, p_reason)
            ELSE notes || E'\n---\n' || TO_CHAR(NOW(), 'DD.MM.YYYY HH24:MI') || 
                E'\nСделка переоткрыта'
        END,
        updated_at = NOW()
    WHERE id = p_deal_id;
    
    RETURN jsonb_build_object(
        'success', TRUE,
        'deal_id', p_deal_id,
        'status', 'open',
        'old_status', v_old_status,
        'company_name', v_company_name,
        'product_name', v_product_name
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object(
            'success', FALSE,
            'error', SQLERRM
        );
END;
$function$
