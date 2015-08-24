----- this function is not part of the solution, but it is very helpful :)
DROP FUNCTION IF EXISTS test.drop_all_function_overloads(text, boolean);
CREATE OR REPLACE FUNCTION test.drop_all_function_overloads(
	arg_function_string text, 
	arg_drop boolean DEFAULT true
    )  RETURNS text AS $BODY$
		DECLARE
		    var_dropscript text:= '';
		    var_found_function_names text[];
		BEGIN
						SELECT ARRAY( 
					SELECT 
						'DROP FUNCTION IF EXISTS '|| format('%I.%I(%s)', ns.nspname, p.proname, oidvectortypes(p.proargtypes))||';' 
						FROM pg_proc p 
						INNER JOIN pg_namespace ns ON (p.pronamespace = ns.oid)
						WHERE ns.nspname LIKE given_strings.schema_substring AND p.proname LIKE given_strings.function_substring
				    ) 
			 FROM
			  (SELECT 
			       COALESCE(substring(arg_function_string from '^(.*)\.'),'%') AS schema_substring,
			       COALESCE(substring(arg_function_string from '^.*\.(.*)'),arg_function_string) AS function_substring)given_strings INTO var_found_function_names;
			SELECT E'-- Dropping '||array_length(var_found_function_names,1)||' functions matching: ' || arg_function_string||' --
			'|| array_to_string(var_found_function_names,'
			') INTO var_dropscript;
			
			IF(arg_drop)THEN   ---- really drop them? 
				EXECUTE var_dropscript;
			END IF;
			RETURN var_dropscript;
		END;
   $BODY$ LANGUAGE plpgsql VOLATILE COST 100;

----- Drop the function using the new types
SELECT test.drop_all_function_overloads('defaults');

---- Valid type names to test
DROP TYPE IF EXISTS "quoted type";
CREATE TYPE "quoted type" AS (t text);

DROP TYPE IF EXISTS "'more"" 'quotes' "" '";
CREATE TYPE "'more"" 'quotes' "" '" AS (t text);

DROP TYPE IF EXISTS "'commas&, '', '', quotes'''";
CREATE TYPE "'commas&, '', '', quotes'''" AS (t text);

DROP TYPE IF EXISTS "', ,"", '', text DEFAULT""'";
CREATE TYPE "', ,"", '', text DEFAULT""'" AS (t text);

DROP TYPE IF EXISTS ", text DEFAULT NULL::text, ";
CREATE TYPE ", text DEFAULT NULL::text, " AS (t text);


------ The function used to demonstrate all parameter string variations
CREATE OR REPLACE FUNCTION public.defaults(
						bigint,													--- anonymous parameter
						has_name bigint, 											--- named parameter
					        "has_name bigint" text,											--- quoted parameter name
					        "'has_name text', 'has_name'" text,									--- quoted name variation 
					        type_name ", text DEFAULT NULL::text, ",					        		--- quoted type example
					        "text DEFAULT NULL::text" ", text DEFAULT NULL::text, " DEFAULT NULL::", text DEFAULT NULL::text, "  	--- totally valid D:					
					)
  RETURNS boolean AS $BODY$
            BEGIN
		RETURN "works";
            END
        $BODY$
  LANGUAGE plpgsql VOLATILE  COST 100;

------- THE QUERY uses pg_proc & information_schema.parameters
 WITH all_function_data AS (
			       SELECT
				p.oid AS poid,
				n.nspname AS schema_name,
				p.proname,
				proargmodes,
				pg_get_function_arguments(p.oid) AS fs,				      
				CASE WHEN array_length(proargmodes,1)<>p.pronargs THEN array_length(proargmodes,1)					
				ELSE p.pronargs END AS arg_num,
				oidvectortypes(p.proargtypes) AS arg_types,		
				string_to_array(p.proargtypes::text,' ') as att, 
				p.proargnames arg_names,  
				COALESCE(p.pronargdefaults,0) as def_num,
				pg_get_expr(proargdefaults, 0) AS def_vals
			       FROM pg_proc p
			       LEFT JOIN pg_namespace n ON n.oid = p.pronamespace WHERE proname = 'defaults'
			),
  known_arg_vals AS (SELECT * FROM (SELECT 
				poid,
				schema_name,
				arg_num,
				def_num,
				fs,
				generate_series(1,arg_num) AS arg_idx,
				oidvectortypes(unnest(att)::oidvector) AS arg_type,
				CASE WHEN arg_names NOTNULL THEN unnest(arg_names) ELSE '' END AS arg_name	,
				def_vals				 
				FROM all_function_data)t),
  full_arg_vals AS(SELECT
				arg_idx,
				poid,
				schema_name,
				arg_num,
				def_num,
				fs, 
				GREATEST(arg_idx-(arg_num - def_num),0) AS def_idx,			
				arg_name,
				arg_type,
				CASE WHEN length(arg_name)>0 THEN '["'''']*'||regexp_replace(arg_name,'[^\w\s]+','.+','g')||'["'''']*\s' ELSE '' END as arg_name_clean,
				'["'''']*'||regexp_replace(arg_type,'[^\w\s]+','.+','g')||'["'''']*'||CASE WHEN(def_num>0 AND (arg_idx-(arg_num - def_num)>0) )THEN '\sDEFAULT\s.*' ELSE '' END  AS arg_type_clean,										
				def_vals
				FROM known_arg_vals k
				LEFT JOIN information_schema.parameters isp ON regexp_replace(isp.specific_name, '(^\w+_)', '', 'g')::oid = k.poid AND ordinal_position=k.arg_idx),
arg_vals_with_defaults AS(
			SELECT 
				arg_idx,
				def_idx,
				regexp_matches(fs,'^'||reg_before||'('||arg_name_clean||arg_type_clean||')'||reg_after||'$') AS found_parameter_string
			  FROM(
				SELECT 
				fv.fs,
				def_num,
				fv.arg_name,
				fv.arg_type,
				arg_idx,
				def_idx
				,fv.arg_name_clean
				,fv.arg_type_clean
				,CASE WHEN arg_idx > 1 THEN array_to_string(ARRAY(SELECT COALESCE(arg_name_clean||'')||arg_type_clean FROM full_arg_vals f WHERE f.arg_idx < fv.arg_idx),',\s')||',\s' ELSE '' END AS reg_before
				,CASE WHEN arg_idx < arg_num THEN '\,\s'||array_to_string(ARRAY(SELECT arg_name_clean||arg_type_clean FROM full_arg_vals f WHERE f.arg_idx > fv.arg_idx),',\s') ELSE '' END AS reg_after
				FROM  full_arg_vals fv
			      ) param_strings
	      )
SELECT * FROM arg_vals_with_defaults;
