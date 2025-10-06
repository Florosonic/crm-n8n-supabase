CREATE OR REPLACE FUNCTION public.upsert_deal(p_company_id uuid, p_contact_id uuid, p_product_name text, p_product_description text, p_price numeric, p_stage integer, p_sample_shipment_date date, p_notes text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_deal_id UUID;
    v_old_stage INTEGER;
    v_stage_changed BOOLEAN := FALSE;
    v_product_name TEXT;
BEGIN
    v_product_name := TRIM(REGEXP_REPLACE(p_product_name, '\s+', ' ', 'g'));
    IF v_product_name = '' OR v_product_name IS NULL THEN
        v_product_name := 'Продукт не указан';
    END IF;
    
    SELECT id, stage INTO v_deal_id, v_old_stage
    FROM deals
    WHERE company_id = p_company_id
      AND LOWER(TRIM(REGEXP_REPLACE(product_name, '\s+', ' ', 'g'))) = LOWER(v_product_name)
      AND status = 'open'
    LIMIT 1;
    
    IF v_deal_id IS NOT NULL THEN
        v_stage_changed := (v_old_stage != p_stage);
        
        UPDATE deals
        SET contact_id = COALESCE(p_contact_id, contact_id),
            product_description = COALESCE(p_product_description, product_description),
            price = COALESCE(p_price, price),
            stage = p_stage,
            sample_shipment_date = COALESCE(p_sample_shipment_date, sample_shipment_date),
            notes = CASE 
                WHEN p_notes IS NOT NULL THEN 
                    COALESCE(TO_CHAR(NOW(), 'DD.MM.YYYY HH24:MI') || E'\n' || p_notes || E'\n---\n' || notes, p_notes)
                ELSE notes
            END,
            updated_at = NOW()
        WHERE id = v_deal_id;
    ELSE
        INSERT INTO deals (
            company_id, contact_id, product_name, product_description,
            price, stage, sample_shipment_date, notes, status
        )
        VALUES (
            p_company_id, p_contact_id, v_product_name, p_product_description,
            p_price, p_stage, p_sample_shipment_date, p_notes, 'open'
        )
        RETURNING id INTO v_deal_id;
        
        v_stage_changed := TRUE;
    END IF;
    
    RETURN jsonb_build_object(
        'deal_id', v_deal_id,
        'stage_changed', v_stage_changed,
        'old_stage', v_old_stage,
        'new_stage', p_stage
    );
END;
$function$
