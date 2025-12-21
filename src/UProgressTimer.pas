unit UProgressTimer;


uses System;


type
  InfoTimerEventHandler = procedure(dt: TimeSpan);
  
  InfoTimer = class(System.Timers.Timer)
    {$region Fields}
    private _StartTime : DateTime;
    private _Locker    : object;
    private _Handler   : InfoTimerEventHandler;
    {$endregion}
    
    {$region Ctors}
    public constructor ();
    begin
      Enabled := false;
      Elapsed += (sender, e) ->
        begin
          if _Handler <> nil then
            _Handler(DateTime.Now - _StartTime);
        end;
    end;
    {$endregion}
    
    {$region Properties}
    public property Locker: object read _Locker; 
    {$endregion}
    
    {$region Methods}
    public procedure Start(interval: integer; handler: InfoTimerEventHandler);
    begin
      Interval   := interval;
      _Handler   := handler;
      _Locker    := new object();
      _StartTime := DateTime.Now;
      Enabled    := true;
      inherited Start();
    end;

    public procedure Stop();
    begin
      inherited Stop();
      Enabled := false;

      _Handler(DateTime.Now - _StartTime);
    end;
    {$endregion}
  end;


end.