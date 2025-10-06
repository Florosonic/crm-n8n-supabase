CREATE OR REPLACE FUNCTION public.get_deals_statistics()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_total INTEGER;
    v_open INTEGER;
    v_won INTEGER;
    v_lost INTEGER;
    v_won_revenue NUMERIC;
BEGIN
    SELECT COUNT(*) INTO v_total FROM deals;
    SELECT COUNT(*) INTO v_open FROM deals WHERE status = 'open';
    SELECT COUNT(*) INTO v_won FROM deals WHERE status = 'won';
    SELECT COUNT(*) INTO v_lost FROM deals WHERE status = 'lost';
    SELECT COALESCE(SUM(price), 0) INTO v_won_revenue FROM deals WHERE status = 'won';
    
    RETURN jsonb_build_object(
        'total_deals', v_total,
        'open_deals', v_open,
        'won_deals', v_won,
        'lost_deals', v_lost,
        'win_rate', CASE 
            WHEN (v_won + v_lost) > 0 THEN 
                ROUND((v_won::NUMERIC / (v_won + v_lost)) * 100, 2)
            ELSE 0 
        END,
        'total_revenue', v_won_revenue
    );
END;
$function$
