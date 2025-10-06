CREATE OR REPLACE FUNCTION public.get_weekly_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_overdue_pings JSONB;
    v_stuck_deals JSONB;
    v_pipeline_stats JSONB;
BEGIN
    -- Просроченные пинги
    SELECT jsonb_agg(row_to_json(t))
    INTO v_overdue_pings
    FROM (
        SELECT 
            c.name as company,
            d.product_name as product,
            p.ping_date,
            p.action,
            (CURRENT_DATE - p.ping_date) as days_overdue
        FROM pings p
        JOIN deals d ON d.id = p.deal_id
        JOIN companies c ON c.id = d.company_id
        WHERE p.ping_date < CURRENT_DATE
          AND p.is_completed = FALSE
        ORDER BY p.ping_date
    ) t;
    
    -- Застрявшие сделки (без движения > 2 недель)
    SELECT jsonb_agg(row_to_json(t))
    INTO v_stuck_deals
    FROM (
        SELECT 
            c.name as company,
            d.product_name as product,
            ps.name as stage,
            d.updated_at::DATE as last_update,
            (CURRENT_DATE - d.updated_at::DATE) as days_inactive
        FROM deals d
        JOIN companies c ON c.id = d.company_id
        JOIN pipeline_stages ps ON ps.id = d.stage
        WHERE d.closed_at IS NULL
          AND d.updated_at < CURRENT_DATE - INTERVAL '14 days'
        ORDER BY d.updated_at
    ) t;
    
    -- Статистика по воронке
    SELECT jsonb_agg(row_to_json(t))
    INTO v_pipeline_stats
    FROM (
        SELECT 
            ps.id as stage,
            ps.name as stage_name,
            COUNT(d.id) as deal_count,
            COALESCE(SUM(d.price), 0) as total_value
        FROM pipeline_stages ps
        LEFT JOIN deals d ON d.stage = ps.id AND d.closed_at IS NULL
        GROUP BY ps.id, ps.name
        ORDER BY ps.id
    ) t;
    
    RETURN jsonb_build_object(
        'overdue_pings', COALESCE(v_overdue_pings, '[]'::JSONB),
        'stuck_deals', COALESCE(v_stuck_deals, '[]'::JSONB),
        'pipeline_stats', COALESCE(v_pipeline_stats, '[]'::JSONB),
        'generated_at', NOW()
    );
END;
$function$
