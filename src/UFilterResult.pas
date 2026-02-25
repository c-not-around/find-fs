unit UFilterResult;


uses System;
uses System.Text.RegularExpressions;


type
  FilterResult = class
    {$region Fields}
    private _Path  : string;
    private _Index : integer;
    private _Length: integer;
    {$endregion}
    
    {$region Ctors}
    public constructor (path: string; &match: System.Text.RegularExpressions.Match);
    begin
      _Path   := path;
      _Index  := &match.Index;
      _Length := &match.Length;
    end;
    {$endregion}
    
    {$region Properties}
    public property Path: string read _Path;
    
    public property MatchIndex: integer read _Index;
    
    public property MatchLength: integer read _Length;
    {$endregion}
  end;


end.