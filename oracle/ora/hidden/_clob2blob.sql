--convert CLOB to BLOB and compress, mainly used to generate sqlplus script
set feed off verify off
var lobresult varchar2(4000);
BEGIN
    :lobresult :=q'[
    DECLARE
        v_clob       CLOB := :LOB;
        v_blob       BLOB;
        v_result     CLOB;
        v_piece      RAW(1000);
        v_linewidth  PLS_INTEGER := 1000;
        dest_offset  INTEGER     := 1;
        src_offset   INTEGER     := 1;
        lob_csid     NUMBER      := dbms_lob.default_csid;
        lang_context INTEGER     := dbms_lob.default_lang_ctx;
        warning      INTEGER;
        PROCEDURE wr(p_line VARCHAR2) IS
        BEGIN
            dbms_lob.writeAppend(v_result, LENGTH(p_line) + 1, p_line || CHR(10));
            --dbms_output.put_line(p_line);
        END;
    BEGIN
        dbms_output.enable(NULL);
        dbms_lob.CreateTemporary(v_blob, TRUE);
        dbms_lob.CreateTemporary(v_result, TRUE);
        dbms_lob.ConvertToBLOB(v_blob, v_clob, dbms_lob.getLength(v_clob), dest_offset, src_offset, lob_csid, lang_context, warning);
        v_blob := utl_compress.lz_compress(v_blob);

        wr('DECLARE');
        wr('    v_clob       CLOB;');
        wr('    v_blob       BLOB;');
        wr('    dest_offset  INTEGER := 1;');
        wr('    src_offset   INTEGER := 1;');
        wr('    lob_csid     NUMBER  := dbms_lob.default_csid;');
        wr('    lang_context INTEGER := dbms_lob.default_lang_ctx;');
        wr('    warning      INTEGER;');
        wr('    procedure ap(p_line raw) is begin dbms_lob.writeAppend(v_blob,utl_raw.length(p_line),p_line);end;');
        wr('BEGIN');
        wr('    dbms_lob.CreateTemporary(v_blob,TRUE);');
        wr('    dbms_lob.CreateTemporary(v_clob,TRUE);');

        dest_offset := 1;
        src_offset  := dbms_lob.getLength(v_blob);
        dbms_output.put_line(src_offset);
        LOOP
            dbms_lob.read(v_blob, v_linewidth, dest_offset, v_piece);
            dest_offset := dest_offset + 1000;
            wr('    ap(''' || v_piece || ''');');
            EXIT WHEN dest_offset > src_offset;
        END LOOP;
        wr('    v_blob := utl_compress.lz_uncompress(v_blob);');
        wr('    dbms_lob.ConvertToCLOB(v_clob, v_blob, dbms_lob.getLength(v_blob), dest_offset, src_offset, lob_csid, lang_context, warning);');
        wr('    :result := v_clob;');
        wr('END;');
        :lob := v_result;
    END;]';
END;
/
