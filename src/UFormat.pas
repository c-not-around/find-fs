unit UFormat;


uses System;
uses System.Globalization;


type
  Format = static class
    private static _FormatInfo := (new CultureInfo('en-US')).NumberFormat;
    
    public static property Info: NumberFormatInfo read _FormatInfo;
    
    public static function BytesPrefix(s: double): string;
    begin
      var p := 0;
      while s >= 1024.0 do
        begin
          s /= 1024.0;
          p += 1;
        end;
      
      var f := string('f');
      if s < 10.0 then
        f += '2'
      else if s < 100.0 then
        f += '1'
      else
        f += '0';
      
      result := s.ToString(f, _FormatInfo);
      
      if p > 0 then
        result += 'kMGTP'[p];
      
      result += 'b';
    end;
  end;
  
  Prefixes = static class
    public const KB = int64(1) shl 10;
    public const MB = int64(1) shl 20;
    public const GB = int64(1) shl 30;
  end;


end.