# stored_procedure_parameter_info
Extracting default values as a list from postgresql stored procedures via quering postgresql system data


## The issue
- There is no clean way to extract defaults values for postgres stored procedure parameters.
- information_schema.parameters lists parameter information but not default values

          SELECT * FROM information_schema.parameters;

- The function pg_get_function_arguments(oid) returns a complete string of parameters, parameter types, and defaults however, because the return value is a string, and the flexibility of postgres type naming, parameter naming, and default values, there is no easy way to seperate them into an array. i.e. string_to_array(str,', ') will fail when a parameter name, type, or default value contains the string ', '

            SELECT pg_get_function_arguments(oid) FROM pg_proc;

- The function pg_get_expr(pg_node_tree,oid) can be used to parse pg_proc.proargdefaults, but also returns the value as a string. This leads to the same issue when the default value contains the string ', '. 
- pg_node_tree can be cast to text and manually split into its individual nodes; unfortunately pg_get_expr only accepts values from system columns.

            SELECT 
                COALESCE(p.pronargdefaults,0) as number_of_defaults,
				pg_get_expr(proargdefaults, 0) AS default_values_as_string 
             FROM pg_proc;

- There's been some discussion as to changing how the defaults were being stored, but no visible resolution. 
[http://www.postgresql.org/message-id/15686.1356105206@sss.pgh.pa.us] 

- The only related threads on stackoverflow say that is not possible to do this, or offer a solution that relies on a regexp split on the string ', ' which as mentioned before, will fail for any arguments with a parameter name, type, or default value containing the substring ', '
- [http://stackoverflow.com/questions/25308765/postgresql-how-can-i-inspect-which-arguments-to-a-procedure-have-a-default-valu]
- [http://stackoverflow.com/questions/30590264/sql-stored-proc-default-parameter-values]
- [http://stackoverflow.com/questions/982798/is-it-possible-to-have-a-default-parameter-for-a-mysql-stored-procedure]

-This solution therefore is anything but elegant. However, thus far, the solution consistently works with nearly every possible parameter name, parameter type, and default value. It basically consists of extracting known argument names, known argument types, and known default and parameter totals and composing a regex string that is essentially:

            SELECT regexp_matches(full_parameter_string, 
                 				known_string_before
                 					||(parameter_data)||
                 						known_string_after
                 		 );

If anyone has a better way to do this, feel free to contribute. This particular postgres behavior puzzle has been driving me nuts for a while, and as mentioned before this solution is anything but elegant.

- Note that these are all valid type names in postgres. Because quotes and double quotes are perfectly valid characters(if correctly terminated.) Therefore regexp exclusion for characters within a set of quotes becomes unfeasable (lookahead/lookbehind regex expressions don't seem to be supported in postgresql reg_exp functions):

             CREATE TYPE "quotes" AS (t text);
             CREATE TYPE "'more quotes'" AS (t text);
             CREATE TYPE "'extra'', '', quotes'''" AS (t text);
             CREATE TYPE "'extra"" '','MORE', "", quotes""'" AS (t text);
             CREATE TYPE ", text DEFAULT 'text DEFAULT'::text, " AS (t text);

- Furthermore, each of the following is a valid parameter definition: (If anyone actually does this, they shoud probably be beaten, but this demonstrates worst case scenarios)

             bigint,	
             has_name bigint, 
             "name in quotes" text,
             "'more quotes'" text,
             type_name_bs ", text DEFAULT NULL::text, " DEFAULT NULL::", text DEFAULT NULL::text, " 
             ', text DEFAULT text DEFAULT::text, ' text DEFAULT 'DEFAULT '', , , ,hello''::text[]'::text

## TODO
- clean up the query names, 
- remove redundant data in sub-queries
- recursively parse full_arg string to shorten/speed up the query
