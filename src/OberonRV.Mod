MODULE OberonRV;
IMPORT Out, ORP;

  PROCEDURE Main;
  VAR 
    argc     : INTEGER;
    i        : INTEGER;
    filename : ARRAY 256 OF CHAR;
  BEGIN
    argc := ARGNUM();
    IF argc = 0 THEN
      Out.String("Usage: OberonRV <source file> ...");
      Out.Ln;
    ELSE
      FOR i := 0 TO argc-1 DO
        ARGS(i, filename);
        ORP.Compile(filename, TRUE); (* always create symbol file *)
      END
    END
  END Main;

END OberonRV.
