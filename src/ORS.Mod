(* copyright (C)2013 Niklaus Wirth (NW), Juerg Gutknecht (JG), Paul Reed (PR/PDR). *)
(* modified by Jörg Mische *)

MODULE ORS; (* NW 19.9.93 / 15.3.2017  Scanner in Oberon-07*)
  IMPORT SYSTEM, Files, Out;

(* Oberon Scanner does lexical analysis. Input is Oberon-Text, output is
  sequence of symbols, i.e identifiers, numbers, strings, and special symbols.
  Recognises all Oberon keywords and skips comments. The keywords are
  recorded in a table.
  Get(sym) delivers next symbol from input text with Reader R.
  Mark(msg) records error and delivers error message with Writer W.
  If Get delivers ident, then the identifier (a string) is in variable id, if int or char
  in ival, if real in rval, and if string in str (and slen) *)
  
  CONST IdLen* = 32;
    NKW = 34;  (*nof keywords*)
    maxExp = 38; stringBufSize = 256;
  
    (*lexical symbols*)
    null = 0; times* = 1; rdiv* = 2; div* = 3; mod* = 4;
    and* = 5; plus* = 6; minus* = 7; or* = 8; eql* = 9;
    neq* = 10; lss* = 11; leq* = 12; gtr* = 13; geq* = 14;
    in* = 15; is* = 16; arrow* = 17; period* = 18;
    char* = 20; int* = 21; real* = 22; false* = 23; true* = 24;
    nil* = 25; string* = 26; not* = 27; lparen* = 28; lbrak* = 29;
    lbrace* = 30; ident* = 31;
    if* = 32; while* = 34; repeat* = 35; case* = 36; for* = 37;
    comma* = 40; colon* = 41; becomes* = 42; upto* = 43; rparen* = 44;
    rbrak* = 45; rbrace* = 46; then* = 47; of* = 48; do* = 49;
    to* = 50; by* = 51; semicolon* = 52; end* = 53; bar* = 54;
    else* = 55; elsif* = 56; until* = 57; return* = 58;
    array* = 60; record* = 61; pointer* = 62; const* = 63; type* = 64;
    var* = 65; procedure* = 66; begin* = 67; import* = 68; module* = 69; eot = 70;

  TYPE Ident* = ARRAY IdLen OF CHAR;

  VAR ival*, slen*: LONGINT;  (*results of Get*)
    rval*: REAL;
    id*: Ident;  (*for identifiers*)
    str*: ARRAY stringBufSize OF CHAR;
    errcnt*: INTEGER;

    ch: CHAR;  (*last character read*)
    FileName: ARRAY 256 OF CHAR; (* input file name *)
    LineNo: INTEGER; (* current line number *)
    LinePos: INTEGER; (* position within line *)
    FilePos: INTEGER; (* offset within file *)
    errpos: LONGINT;
    R: Files.File;
    k: INTEGER;
    KWX: ARRAY 10 OF INTEGER;
    keyTab: ARRAY NKW OF
        RECORD sym: INTEGER; id: ARRAY 12 OF CHAR END;

  PROCEDURE ReadChar;
  BEGIN LineNo := 0;
    ch := Files.ReadChar(R);
    IF ch = 0AX THEN
      LinePos := 0;
      INC(LineNo);
    ELSE
      INC(LinePos);
    END;
    INC(FilePos);
  END ReadChar;

  PROCEDURE CopyId*(VAR ident: Ident);
  BEGIN ident := id
  END CopyId;

  PROCEDURE Pos*(): LONGINT;
  BEGIN RETURN FilePos - 1
  END Pos;

  PROCEDURE Mark*(msg: ARRAY OF CHAR);
  BEGIN
    IF (FilePos > errpos) & (errcnt < 25) THEN
      Out.Ln;
      Out.String(FileName);
      Out.String(":");
      Out.Int(LineNo, 1);
      Out.String(":");
      Out.Int(LinePos, 1);
      Out.String(": ");
      Out.String(msg);
    END ;
    INC(errcnt); errpos := FilePos + 4
  END Mark;

  PROCEDURE Identifier(VAR sym: INTEGER);
    VAR i, k: INTEGER;
  BEGIN i := 0;
    REPEAT
      IF i < IdLen-1 THEN id[i] := ch; INC(i) END ;
      ReadChar
    UNTIL (ch < "0") OR (ch > "9") & (ch < "A") OR (ch > "Z") & (ch < "a") OR (ch > "z");
    id[i] := 0X; 
    IF i < 10 THEN k := KWX[i-1];  (*search for keyword*)
      WHILE (id # keyTab[k].id) & (k < KWX[i]) DO INC(k) END ;
      IF k < KWX[i] THEN sym := keyTab[k].sym ELSE sym := ident END
    ELSE sym := ident
    END
  END Identifier;

  PROCEDURE String;
    VAR i: INTEGER;
  BEGIN i := 0; ReadChar;
    WHILE (Files.Status(R) = Files.OK) & (ch # 22X) DO
      IF ch >= " " THEN
        IF i < stringBufSize-1 THEN str[i] := ch; INC(i) ELSE Mark("string too long") END ;
      END ;
      ReadChar
    END ;
    str[i] := 0X; INC(i); ReadChar; slen := i
  END String;

  PROCEDURE HexString;
    VAR i, m, n: INTEGER;
  BEGIN i := 0; ReadChar;
    WHILE (Files.Status(R) = Files.OK) & (ch # "$") DO
      WHILE (Files.Status(R) = Files.OK) & (ch <= " ") DO ReadChar END ;  (*skip*)
      IF ("0" <= ch) & (ch <= "9") THEN m := ORD(ch) - 30H
      ELSIF ("A" <= ch) & (ch <= "F") THEN m := ORD(ch) - 37H
      ELSE m := 0; Mark("hexdig expected")
      END ;
      ReadChar;
      IF ("0" <= ch) & (ch <= "9") THEN n := ORD(ch) - 30H
      ELSIF ("A" <= ch) & (ch <= "F") THEN n := ORD(ch) - 37H
      ELSE n := 0; Mark("hexdig expected")
      END ;
      IF i < stringBufSize THEN str[i] := CHR(m*10H + n); INC(i) ELSE Mark("string too long") END ;
      ReadChar
    END ;
    ReadChar; slen := i  (*no 0X appended!*)
  END HexString;

  PROCEDURE Ten(e: LONGINT): REAL;
    VAR x, t: REAL;
  BEGIN x := 1.0; t := 10.0;
    WHILE e > 0 DO
      IF ODD(e) THEN x := t * x END ;
      t := t * t; e := e DIV 2
    END ;
    RETURN x
  END Ten;

  PROCEDURE Number(VAR sym: INTEGER);
    CONST max = 2147483647 (*2^31 - 1*);
    VAR i, k, e, n, s, h: LONGINT; x: REAL;
      d: ARRAY 16 OF INTEGER;
      negE: BOOLEAN;
  BEGIN ival := 0; i := 0; n := 0; k := 0;
    REPEAT
      IF n < 16 THEN d[n] := ORD(ch)-30H; INC(n) ELSE Mark("too many digits"); n := 0 END ;
      ReadChar
    UNTIL (ch < "0") OR (ch > "9") & (ch < "A") OR (ch > "F");
    IF (ch = "H") OR (ch = "R") OR (ch = "X") THEN  (*hex*)
      REPEAT h := d[i];
        IF h >= 10 THEN h := h-7 END ;
        k := k*10H + h; INC(i) (*no overflow check*)
      UNTIL i = n;
      IF ch = "X" THEN sym := char;
        IF k < 100H THEN ival := k ELSE Mark("illegal value"); ival := 0 END
      ELSIF ch = "R" THEN sym := real; rval := SYSTEM.VAL(REAL, k)
      ELSE sym := int; ival := k
      END ;
      ReadChar
    ELSIF ch = "." THEN
      ReadChar;
      IF ch = "." THEN (*double dot*) ch := 7FX;  (*decimal integer*)
        REPEAT
          IF d[i] < 10 THEN
            IF k <= (max-d[i]) DIV 10 THEN k := k *10 + d[i] ELSE Mark("too large"); k := 0 END
          ELSE Mark("bad integer")
          END ;
          INC(i)
        UNTIL i = n;
        sym := int; ival := k
      ELSE (*real number*) x := 0.0; e := 0;
        REPEAT  (*integer part*) x := x * 10.0 + FLT(d[i]); INC(i) UNTIL i = n;
        WHILE (ch >= "0") & (ch <= "9") DO  (*fraction*)
          x := x * 10.0 + FLT(ORD(ch) - 30H); DEC(e); ReadChar
        END ;
        IF (ch = "E") OR (ch = "D") THEN  (*scale factor*)
          ReadChar; s := 0; 
          IF ch = "-" THEN negE := TRUE; ReadChar
          ELSE negE := FALSE;
            IF ch = "+" THEN ReadChar END
          END ;
          IF (ch >= "0") & (ch <= "9") THEN
            REPEAT s := s*10 + ORD(ch)-30H; ReadChar
            UNTIL (ch < "0") OR (ch >"9");
            IF negE THEN e := e-s ELSE e := e+s END
          ELSE Mark("digit?")
          END
        END ;
        IF e < 0 THEN
          IF e >= -maxExp THEN x := x / Ten(-e) ELSE x := 0.0 END
        ELSIF e > 0 THEN
          IF e <= maxExp THEN x := Ten(e) * x ELSE x := 0.0; Mark("too large") END
        END ;
        sym := real; rval := x
      END
    ELSE  (*decimal integer*)
      REPEAT
        IF d[i] < 10 THEN
          IF k <= (max-d[i]) DIV 10 THEN k := k*10 + d[i] ELSE Mark("too large"); k := 0 END
        ELSE Mark("bad integer")
        END ;
        INC(i)
      UNTIL i = n;
      sym := int; ival := k
    END
  END Number;

  PROCEDURE comment;
  BEGIN ReadChar;
    REPEAT
      WHILE (Files.Status(R) = Files.OK) & (ch # "*") DO
        IF ch = "(" THEN ReadChar;
          IF ch = "*" THEN comment END
        ELSE ReadChar
        END
      END ;
      WHILE ch = "*" DO ReadChar END
    UNTIL (ch = ")") OR (Files.Status(R) # Files.OK);
    IF Files.Status(R) = Files.OK THEN ReadChar ELSE Mark("unterminated comment") END
  END comment;

  PROCEDURE Get*(VAR sym: INTEGER);
  BEGIN
    REPEAT
      WHILE (Files.Status(R) = Files.OK) & (ch <= " ") DO ReadChar END;
      IF (Files.Status(R) # Files.OK) THEN sym := eot
      ELSIF ch < "A" THEN
        IF ch < "0" THEN
          IF ch = 22X THEN String; sym := string
          ELSIF ch = "#" THEN ReadChar; sym := neq
          ELSIF ch = "$" THEN HexString; sym := string
          ELSIF ch = "&" THEN ReadChar; sym := and
          ELSIF ch = "(" THEN ReadChar; 
            IF ch = "*" THEN sym := null; comment ELSE sym := lparen END
          ELSIF ch = ")" THEN ReadChar; sym := rparen
          ELSIF ch = "*" THEN ReadChar; sym := times
          ELSIF ch = "+" THEN ReadChar; sym := plus
          ELSIF ch = "," THEN ReadChar; sym := comma
          ELSIF ch = "-" THEN ReadChar; sym := minus
          ELSIF ch = "." THEN ReadChar;
            IF ch = "." THEN ReadChar; sym := upto ELSE sym := period END
          ELSIF ch = "/" THEN ReadChar; sym := rdiv
          ELSE ReadChar; (* ! % ' *) sym := null
          END
        ELSIF ch < ":" THEN Number(sym)
        ELSIF ch = ":" THEN ReadChar;
          IF ch = "=" THEN ReadChar; sym := becomes ELSE sym := colon END 
        ELSIF ch = ";" THEN ReadChar; sym := semicolon
        ELSIF ch = "<" THEN  ReadChar;
          IF ch = "=" THEN ReadChar; sym := leq ELSE sym := lss END
        ELSIF ch = "=" THEN ReadChar; sym := eql
        ELSIF ch = ">" THEN ReadChar;
          IF ch = "=" THEN ReadChar; sym := geq ELSE sym := gtr END
        ELSE (* ? @ *) ReadChar; sym := null
        END
      ELSIF ch < "[" THEN Identifier(sym)
      ELSIF ch < "a" THEN
        IF ch = "[" THEN sym := lbrak
        ELSIF ch = "]" THEN  sym := rbrak
        ELSIF ch = "^" THEN sym := arrow
        ELSE (* _ ` *) sym := null
        END ;
        ReadChar
      ELSIF ch < "{" THEN Identifier(sym) ELSE
        IF ch = "{" THEN sym := lbrace
        ELSIF ch = "}" THEN sym := rbrace
        ELSIF ch = "|" THEN sym := bar
        ELSIF ch = "~" THEN  sym := not
        ELSIF ch = 7FX THEN  sym := upto
        ELSE sym := null
        END ;
        ReadChar
      END
    UNTIL sym # null
  END Get;

  PROCEDURE Init*(name: ARRAY OF CHAR);
  BEGIN
    errpos := 0; errcnt := 0;
    FileName := name;
    LineNo := 0;
    LinePos := 0;
    R := Files.Open(name);
    IF R = NIL THEN
      Mark("source file not found")
    END;
    ReadChar
  END Init;


  PROCEDURE EnterKW(sym: INTEGER; name: ARRAY OF CHAR);
  BEGIN keyTab[k].id := name; keyTab[k].sym := sym; INC(k)
  END EnterKW;

BEGIN k := 0; KWX[0] := 0; KWX[1] := 0;
  EnterKW(if, "IF");
  EnterKW(do, "DO");
  EnterKW(of, "OF");
  EnterKW(or, "OR");
  EnterKW(to, "TO");
  EnterKW(in, "IN");
  EnterKW(is, "IS");
  EnterKW(by, "BY");
  KWX[2] := k;
  EnterKW(end, "END");
  EnterKW(nil, "NIL");
  EnterKW(var, "VAR");
  EnterKW(div, "DIV");
  EnterKW(mod, "MOD");
  EnterKW(for, "FOR");
  KWX[3] := k;
  EnterKW(else, "ELSE");
  EnterKW(then, "THEN");
  EnterKW(true, "TRUE");
  EnterKW(type, "TYPE");
  EnterKW(case, "CASE");
  KWX[4] := k;
  EnterKW(elsif, "ELSIF");
  EnterKW(false, "FALSE");
  EnterKW(array, "ARRAY");
  EnterKW(begin, "BEGIN");
  EnterKW(const, "CONST");
  EnterKW(until, "UNTIL");
  EnterKW(while, "WHILE");
  KWX[5] := k;
  EnterKW(record, "RECORD");
  EnterKW(repeat, "REPEAT");
  EnterKW(return, "RETURN");
  EnterKW(import, "IMPORT");
  EnterKW(module, "MODULE");
  KWX[6] := k;
  EnterKW(pointer, "POINTER");
  KWX[7] := k; KWX[8] := k;
  EnterKW(procedure, "PROCEDURE");
  KWX[9] := k
END ORS.
