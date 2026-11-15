separate (Ada_Quality_Test_Suite)
procedure Run_Finding_Identity_Test is
   Rule    : constant String := "rule:with:colons";
   Path    : constant String := "src/path:with:colons.adb";
   Message : constant String := "message:with:colons";
   Key     : constant String :=
     Ada_Quality.Finding_Identity.Create (SRC_01, Rule, Path, Message);
   Contextual : constant String :=
     Ada_Quality.Finding_Identity.Create (SRC_01, Rule, Path, Message, "  nearby source  ");
   Legacy : constant String := "SRC-01:" & Rule & ":" & Path & ":" & Message;
begin
   Assert
     (Ada_Quality.Finding_Identity.Matches (Key, SRC_01, Rule, Path, Message),
      "canonical length-framed finding identity round trips");
   Assert
     (Ada_Quality.Finding_Identity.Matches (Contextual, SRC_01, Rule, Path, Message),
      "contextual finding identity round trips");
   Assert
     (not Ada_Quality.Finding_Identity.Matches (Key, SRC_02, Rule, Path, Message) and then
      not Ada_Quality.Finding_Identity.Matches (Key, SRC_01, "other", Path, Message),
      "structured field mismatches are rejected");
   Assert
     (not Ada_Quality.Finding_Identity.Matches (Legacy, SRC_01, Rule, Path, Message),
      "delimiter-based identities cannot enter new lossless evidence");
   Assert
     (not Ada_Quality.Finding_Identity.Matches
        ("SRC-01:a:b:c:d", SRC_01, "a:b", "c", "d") and then
      not Ada_Quality.Finding_Identity.Matches
        ("SRC-01:a:b:c:d", SRC_01, "a", "b:c", "d"),
      "legacy delimiter aliases cannot identify either side of a structural collision");
   Assert
     (Ada_Quality.Finding_Identity.Matches (Key & "#2", SRC_01, Rule, Path, Message) and then
      not Ada_Quality.Finding_Identity.Matches (Key & "#0", SRC_01, Rule, Path, Message) and then
      not Ada_Quality.Finding_Identity.Matches (Key & "#1", SRC_01, Rule, Path, Message) and then
      not Ada_Quality.Finding_Identity.Matches (Key & "#02", SRC_01, Rule, Path, Message),
      "occurrence suffixes use canonical numbering beginning at two");
   Assert
     (not Ada_Quality.Finding_Identity.Matches (Key & "!", SRC_01, Rule, Path, Message) and then
      not Ada_Quality.Finding_Identity.Matches
        ("SRC-01:v2:01:a1:b1:c", SRC_01, "a", "b", "c") and then
      not Ada_Quality.Finding_Identity.Matches
        ("SRC-01:v2:x:a1:b1:c", SRC_01, "a", "b", "c") and then
      not Ada_Quality.Finding_Identity.Matches
        ("SRC-01:v2:999999999999999999999999999:x", SRC_01, "a", "b", "c"),
      "malformed framing and overflowing lengths are rejected");
   Assert
     (not Ada_Quality.Finding_Identity.Matches
        (Contextual (Contextual'First .. Contextual'Last - 1) & "G", SRC_01, Rule, Path, Message) and then
      not Ada_Quality.Finding_Identity.Matches
        (Contextual (Contextual'First .. Contextual'Last - 1), SRC_01, Rule, Path, Message),
      "context hashes require exactly sixteen lowercase hexadecimal digits");
   Assert
     (Ada_Quality.Finding_Identity.Legacy_Key (Contextual) = Legacy and then
      Ada_Quality.Finding_Identity.Legacy_Key (Key & "#2") = Legacy & "#2" and then
      Ada_Quality.Finding_Identity.Legacy_Key ("malformed:v2:key") = "malformed:v2:key",
      "legacy compatibility aliases are derived only from valid identities");
   declare
      Empty_Key : constant String := Ada_Quality.Finding_Identity.Create (STR_01, "", "", "");
      Padded    : constant String := "[" & Key & "]";
      Rebased   : constant String := Padded (Padded'First + 1 .. Padded'Last - 1);
   begin
      Assert
        (Ada_Quality.Finding_Identity.Matches (Empty_Key, STR_01, "", "", ""),
         "empty framed fields remain canonical");
      Assert
        (Rebased'First /= 1 and then
         Ada_Quality.Finding_Identity.Matches (Rebased, SRC_01, Rule, Path, Message),
         "identity parsing is independent of the input string lower bound");
   end;
end Run_Finding_Identity_Test;
