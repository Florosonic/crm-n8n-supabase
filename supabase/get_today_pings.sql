CREATE OR REPLACE FUNCTION public.get_today_pings()
 RETURNS TABLE(ping_id uuid, ping_date date, action text, company_name text, contact_name text, contact_email text, product_name text, stage integer, stage_name text, last_notes text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT 
        p.id as ping_id,
        p.ping_date,
        p.action,
        c.name as company_name,
        COALESCE(cnt.first_name || ' ' || cnt.last_name, 'Контакт не указан') as contact_name,
        cnt.email as contact_email,
        d.product_name,
        d.stage,
        ps.name as stage_name,
        d.notes as last_notes
    FROM pings p
    JOIN deals d ON d.id = p.deal_id
    JOIN companies c ON c.id = d.company_id
    LEFT JOIN contacts cnt ON cnt.id = d.contact_id
    JOIN pipeline_stages ps ON ps.id = d.stage
    WHERE p.ping_date <= CURRENT_DATE
      AND p.is_completed = FALSE
    ORDER BY p.ping_date, c.name;
END;
$function$
