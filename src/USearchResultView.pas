unit USearchResultView;


{$reference System.Drawing.dll}
{$reference System.Windows.Forms.dll}


uses System;
uses System.Drawing;
uses System.Windows.Forms;
uses UFilterResult;


type
  SearchResultNode = class(TreeNode)
    {$region Fields}
    private _Result: FilterResult;
    {$endregion}
    
    {$region Ctors}
    public constructor (FilterMatch: FilterResult; IconKey: string; NodeMenu: System.Windows.Forms.ContextMenuStrip);
    begin
      _Result := FilterMatch;
      
      Text             := _Result.Path;
      ImageKey         := IconKey;
      SelectedImageKey := IconKey;
      ContextMenuStrip := NodeMenu;
    end;
    {$endregion}
    
    {$region Properties}
    property &Result: FilterResult read _Result;
    {$endregion}
  end;
  
  MatchTreeView = class(TreeView)
    {$region Fields}
    private _Selection : System.Drawing.Brush;
    private _NodeColor : System.Drawing.Color;
    private _MatchColor: System.Drawing.Color;
    {$endregion}
    
    {$region Drawing}
    private procedure DrawFragment(g: Graphics; text: string; var x: integer; y: integer; b: boolean := false);
    begin
      var size := TextRenderer.MeasureText(g, text, Font, System.Drawing.Size.Empty, TextFormatFlags.NoPadding);
      
      if b then
        g.FillRectangle(Brushes.Yellow, x, y, size.Width, size.Height);
      
      TextRenderer.DrawText(g, text, Font, new Point(x, y), b ? _MatchColor : _NodeColor, TextFormatFlags.NoPadding);
      
      x += size.Width;
    end;
    
    protected procedure OnDrawNode(e: DrawTreeNodeEventArgs); override;
    begin
      inherited OnDrawNode(e);
      
      if not e.Node.IsVisible then
        exit;
      
      if (e.State and TreeNodeStates.Selected) = TreeNodeStates.Selected then
        e.Graphics.FillRectangle(_Selection, e.Bounds)
      else
        e.Graphics.FillRectangle(SystemBrushes.Window, e.Bounds);
      
      var CurrentX := e.Bounds.X;
      
      if e.Node is SearchResultNode then
        begin
          var node := e.Node as SearchResultNode;
          
          var HighlightIndex  := node.Result.MatchIndex;
          var HighlightLength := node.Result.MatchLength;
          
          if HighlightIndex > 0 then
            begin
              var text := node.Result.Path.Substring(0, HighlightIndex);
              DrawFragment(e.Graphics, text, CurrentX, e.Bounds.Y);
            end;
          
          if (HighlightLength > 0) and (HighlightIndex < node.Result.Path.Length) then
            begin
              var length := Math.Min(HighlightLength, node.Result.Path.Length - HighlightIndex);
              var text   := node.Result.Path.Substring(HighlightIndex, length);
              DrawFragment(e.Graphics, text, CurrentX, e.Bounds.Y, true);
            end;
          
          if (HighlightIndex + HighlightLength) < node.Result.Path.Length then
            begin
              var text := node.Result.Path.Substring(HighlightIndex + HighlightLength);
              DrawFragment(e.Graphics, text, CurrentX, e.Bounds.Y);
            end;
        end
      else
        DrawFragment(e.Graphics, e.Node.Text, CurrentX, e.Bounds.Y);
    end;
    {$endregion}
    
    {$region Ctors}
    public constructor ();
    begin
      inherited Create();
      
      SetStyle(ControlStyles.AllPaintingInWmPaint, true);
      SetStyle(ControlStyles.OptimizedDoubleBuffer, true);
      
      DrawMode := TreeViewDrawMode.OwnerDrawText;
      
      _Selection  := new SolidBrush(System.Drawing.Color.FromArgb(232, 232, 255));
      _NodeColor  := Color.Black;
      _MatchColor := Color.Red;
    end;
    {$endregion}
  end;

end.