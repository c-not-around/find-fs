unit FindFsMainForm;


{$reference System.Drawing.dll}
{$reference System.Windows.Forms.dll}

{$resource res\icon.ico}
{$resource res\open.png}
{$resource res\save.png}
{$resource res\copy.png}
{$resource res\paste.png}
{$resource res\clear.png}
{$resource res\cut.png}
{$resource res\delete.png}
{$resource res\find.png}
{$resource res\error.png}
{$resource res\folder.png}
{$resource res\file.png}


uses System;
uses System.IO;
uses System.Text;
uses System.Text.RegularExpressions;
uses System.Globalization;
uses System.Threading;
uses System.Threading.Tasks;
uses System.Diagnostics;
uses System.Drawing;
uses System.Windows.Forms;
uses Extensions;


type
  PathsNames = array of string;
  
  MainForm = class(Form)
    {$region Fields}
    private _MainContainer     : SplitContainer;
    private _LeftContainer     : SplitContainer;
    private _PathsListMenu     : System.Windows.Forms.ContextMenuStrip;
    private _PathsList         : TextBox;
    private _FindFiltersMenu   : System.Windows.Forms.ContextMenuStrip;
    private _FindFilters       : TextBox;
    private _ResultsMenu       : System.Windows.Forms.ContextMenuStrip;
    private _ResultNodeMenu    : System.Windows.Forms.ContextMenuStrip;
    private _Results           : TreeView;
    private _ActionsBox        : Panel;
    private _FindButton        : Button;
    private _SaveResults       : Button;
    private _SearchProgress    : ProgressBar;
    private _StatusBar         : StatusStrip;
    private _ElapsedInfo       : ToolStripStatusLabel;
    private _RemainingInfo     : ToolStripStatusLabel;
    private _FilesCountInfo    : ToolStripStatusLabel;
    private _StageInfo         : ToolStripStatusLabel;
    private _ProgressTimer     : System.Timers.Timer;
    private _StartTime         : DateTime;
    private _TotalFilesLocker  : object;
    private _TotalFilesCount   : integer;
    private _CompletedLocker   : object;
    private _CompletedFiles    : integer;
    private _TotalFiltersCount : integer;
    private _CompletedFilters  : integer;
    private _FindAbort         : boolean;
    {$endregion}
    
    {$region Handlers}
    private procedure FindButtonClick(sender: object; e: EventArgs);
    begin
      _FindButton.Enabled := false;
      
      if _FindButton.Text = 'Find' then
        begin
          var paths   := _pathsList.Lines;
          var filters := _FindFilters.Lines;
          
          Task.Factory.StartNew(() -> FindTask(paths, filters));
        end
      else
        _FindAbort := true;
    end;
    
    private procedure SaveResultsClick(sender: object; e: EventArgs);
    begin
      var dialog          := new SaveFileDialog();
      dialog.DefaultExt   := 'list';
      dialog.Filter       := 'File names list (*.list)|*.list|' +
                             'Plain text file (*.txt)|*.txt';
      dialog.AddExtension := true;
      dialog.Title        := 'Select file';
      
      if dialog.ShowDialog() = System.Windows.Forms.DialogResult.OK then
        begin
          var writer := &File.AppendText(dialog.FileName);
          
          foreach var filter: TreeNode in _Results.Nodes do
            begin
              writer.WriteLine($'[{filter.Text}]');
              
              foreach var line: TreeNode in filter.Nodes do
                writer.WriteLine(line.Text);
              
              writer.WriteLine();
            end;
          
          writer.Close();
          writer.Dispose();
        end;
    end;
    {$endregion}
    
    {$region Routines}
    private procedure ResultMenuManageAbility();
    begin
      _SaveResults.Enabled          := _Results.Nodes.Count > 0;
      _ResultsMenu.Items[0].Enabled := _SaveResults.Enabled;
      _ResultsMenu.Items[1].Enabled := _SaveResults.Enabled;
    end;
    
    private procedure AddSourcePath(path: string);
    begin
      var lines := _PathsList.Text;
          
      if lines.Length > 0 then
        lines := lines.TrimEnd(#13, #10) + #13#10;
          
      _PathsList.Text := lines + path;
    end;
    
    private procedure LoadProgressUpdate();
    begin
      var dt      := DateTime.Now - _StartTime;
      var elapsed := $'Elapsed: {dt.Hours}:{dt.Minutes:d2}:{dt.Seconds:d2}';
      var files   := $'Files: {_TotalFilesCount}';
      
      Invoke(() ->
        begin
          _ElapsedInfo.Text    := elapsed;
          _FilesCountInfo.Text := files;
        end
      );
    end;
    
    private procedure FindProgressUpdate();
    begin
      var total    := _TotalFilesCount * _TotalFiltersCount;
      var progress := Math.Min(_TotalFilesCount * _CompletedFilters + _CompletedFiles, total);
      var dt       := DateTime.Now - _StartTime;
      
      var percent := Convert.ToInt32(100.0 * progress / total);
      
      var remaininig := 'Remaining: ';
      if progress > 0 then
        begin
          var v := progress / dt.Ticks;
          var t := new TimeSpan(Convert.ToInt64((total - progress) / v));
          remaininig += $'{t.Hours}:{t.Minutes:d2}:{t.Seconds:d2}';
        end
      else
        remaininig += $'-:--:--';
      
      var elapsed := $'Elapsed: {dt.Hours}:{dt.Minutes:d2}:{dt.Seconds:d2}';
      var files   := $'Files: {_CompletedFiles}/{_TotalFilesCount}';
      var filters := $'Apply filters: {_CompletedFilters}/{_TotalFiltersCount}';
      
      Invoke(() ->
        begin
          if percent > _SearchProgress.Value then
            _SearchProgress.Value := percent;
          _ElapsedInfo.Text    := elapsed;
          _RemainingInfo.Text  := remaininig;
          _FilesCountInfo.Text := files;
          _StageInfo.Text      := filters;
        end
      );
    end;
    
    private procedure ProgressTimerLoadElapsed(sender: object; e: System.Timers.ElapsedEventArgs) := LoadProgressUpdate();
    
    private procedure ProgressTimerFindElapsed(sender: object; e: System.Timers.ElapsedEventArgs) := FindProgressUpdate();
    
    private procedure BuildLinearFilesList(path: string; FilesList, ErrorList: List<string>);
    begin
      if Directory.Exists(path) and not _FindAbort then
        begin
          var files  : array of string := nil;
          var folders: array of string := nil;
          
          try
            folders := Directory.GetDirectories(path);
            files   := Directory.GetFiles(path);
          except on ex: Exception do
            ErrorList.Add($'"{path}" access error: {ex.Message}');
          end;
          
          if folders <> nil then
            foreach var f: string in folders do
              BuildLinearFilesList(f, FilesList, ErrorList);
          
          if files <> nil then
            begin
              foreach var f: string in files do
                FilesList.Add(f);
              
              lock _TotalFilesLocker do
                _TotalFilesCount += files.Length;
            end;
        end;
    end;
    
    private procedure FindTask(paths, filters: array of string);
    begin
      _FindAbort := false;
      
      Invoke(() ->
        begin
          Cursor                := Cursors.WaitCursor;
          _SearchProgress.Value := 0;
          _FilesCountInfo.Text  := 'Files: -/-';
          _StageInfo.Text       := 'Create files list ...';
          _FindButton.Text      := 'Abort';
          _FindButton.Enabled   := true;
        end
      );
      
      var files  := new List<string>();
      var errors := new List<string>();
      
      _StartTime              := DateTime.Now;
      _ProgressTimer.Interval := 500.0;
      _ProgressTimer.Elapsed  += ProgressTimerLoadElapsed;
      _ProgressTimer.Enabled  := true;
      _ProgressTimer.Start();
      
      _TotalFilesCount  := 0;
      _TotalFilesLocker := new Object();
      
      foreach var path: string in paths do
        BuildLinearFilesList(path, files, errors);
      
      _ProgressTimer.Stop();
      _ProgressTimer.Enabled := false;
      _ProgressTimer.Elapsed -= ProgressTimerLoadElapsed;
      
      Invoke(() ->
        begin
          LoadProgressUpdate();
          Cursor := Cursors.Default;
        end
      );
      
      if not _FindAbort then
        begin
          var FindNode              := new TreeNode(DateTime.Now.ToString('yyyy-MM-dd HH:mm:ss'));
          FindNode.ImageKey         := 'find';
          FindNode.SelectedImageKey := 'find';
          
          if errors.Count > 0 then
            begin
              var ErrorsNode              := new TreeNode();
              ErrorsNode.Text             := $'Files list build with {errors.Count} errors';
              ErrorsNode.ImageKey         := 'error';
              ErrorsNode.SelectedImageKey := 'error';
              ErrorsNode.ContextMenuStrip := _ResultNodeMenu;
              
              foreach var line: string in errors do
                begin
                  var node              := new TreeNode();
                  node.Text             := line;
                  node.ForeColor        := Color.Red;
                  node.ImageKey         := 'folder';
                  node.SelectedImageKey := 'folder';
                  node.ContextMenuStrip := _ResultNodeMenu;
                  ErrorsNode.Nodes.Add(node);
                end;
              
              FindNode.Nodes.Add(ErrorsNode);
            end;
          
          Invoke(() ->
            begin
              _ElapsedInfo.Text     := 'Elapsed: 0:00:00';
              _RemainingInfo.Text   := 'Remaining: -:--:--';
              _FilesCountInfo.Text  := $'Files: 0/{_TotalFilesCount}';
              _StageInfo.Text       := $'Apply filters: 0/{filters.Length}';
            end
          );
          
          _TotalFiltersCount := filters.Length;
          _CompletedFilters  := 0;
          _CompletedLocker   := new Object();
          
          _StartTime              := DateTime.Now;
          _ProgressTimer.Interval := 500.0;
          _ProgressTimer.Elapsed  += ProgressTimerFindElapsed;
          _ProgressTimer.Enabled  := true;
          _ProgressTimer.Start();
          
          foreach var filter: string in filters do
            begin
              lock _CompletedLocker do
                _CompletedFiles := 0;
              
              var regexp : Regex;
              var regerr := '';
              var results: List<string>;
              
              try
                regexp  := new Regex(filter, RegexOptions.IgnoreCase);
                results := new List<string>();
                
                foreach var f: string in files do
                  begin
                    if regexp.IsMatch(f) then
                      results.Add(f);
                    
                    lock _CompletedLocker do
                      _CompletedFiles += 1;
                    
                    if _FindAbort then
                      break;
                  end;
              except on ex: Exception do
                regerr := ex.Message;
              end;
              
              lock _CompletedLocker do
               _CompletedFilters += 1;
              
              var FilterNode              := new TreeNode();
              FilterNode.ImageKey         := 'folder';
              FilterNode.SelectedImageKey := 'folder';
              FilterNode.ContextMenuStrip := _ResultNodeMenu;
              
              if regerr = '' then
                begin
                  FilterNode.Text := $'Filter "{filter}" {results.Count} matches';
                  
                  if results.Count > 0 then
                    foreach var line: string in results do
                      begin
                        var node              := new TreeNode(line);
                        node.ImageKey         := 'file';
                        node.SelectedImageKey := 'file';
                        node.ContextMenuStrip := _ResultNodeMenu;
                        FilterNode.Nodes.Add(node);
                      end
                  else
                    FilterNode.ToolTipText := 'No results for this filter';
                end
              else
                begin
                  FilterNode.Text      := $'Filter "{filter}" error: {regerr}';
                  FilterNode.ForeColor := Color.Red;
                end;
              
              FindNode.Nodes.Add(FilterNode);
              
              if _FindAbort then
                break;
            end;
          
          _ProgressTimer.Stop();
          _ProgressTimer.Enabled := false;
          _ProgressTimer.Elapsed -= ProgressTimerFindElapsed;
          
          Invoke(() -> FindProgressUpdate());
          
          if not _FindAbort then
            Invoke(() ->
              begin
                _Results.Nodes.Add(FindNode);
                FindNode.Expand();
              end
            );
        end;
            
      if not _FindAbort then
        Invoke(() ->
          begin
            _StageInfo.Text := _FindAbort ? 'Aborted.' : 'Done.';
          end
        );
      
      Invoke(() ->
        begin
          _FindButton.Text    := 'Find';
          _FindButton.Enabled := true;
          ResultMenuManageAbility();
        end
      );
    end;
    {$endregion}
    
    {$region Ctors}
    public constructor ();
    begin
      {$region MainForm}
      ClientSize    := new System.Drawing.Size(500, 500);
      MinimumSize   := Size;
      Icon          := Resources.Icon('icon.ico');
      StartPosition := FormStartPosition.CenterScreen;
      Text          := 'Find•Fs';
      {$endregion}
      
      {$region MainContainer}
      _MainContainer               := new SplitContainer();
      _MainContainer.Location      := new Point(3, 3);
      _MainContainer.Size          := new System.Drawing.Size(ClientSize.Width - 6, ClientSize.Height - 50 - 6);
      _MainContainer.Anchor        := AnchorStyles.Left or AnchorStyles.Top or AnchorStyles.Right or AnchorStyles.Bottom;
      _MainContainer.BorderStyle   := System.Windows.Forms.BorderStyle.None;
      _MainContainer.BackColor     := Color.LightGray;
      _MainContainer.Panel1MinSize := 200;
      _MainContainer.Panel2MinSize := 200;
      _MainContainer.SplitterWidth := 5;
      {$endregion}
      
      {$region LeftContainer}
      _LeftContainer               := new SplitContainer();
      _LeftContainer.Location      := new Point(0, 0);
      _LeftContainer.Size          := _MainContainer.Panel1.Size;
      _LeftContainer.Dock          := DockStyle.Fill;
      _LeftContainer.BorderStyle   := System.Windows.Forms.BorderStyle.None;
      _LeftContainer.BackColor     := Color.LightGray;
      _LeftContainer.Orientation   := Orientation.Horizontal;
      _LeftContainer.Panel1MinSize := 200;
      _LeftContainer.Panel2MinSize := 200;
      _LeftContainer.SplitterWidth := 5;
      _MainContainer.Panel1.Controls.Add(_LeftContainer);
      {$endregion}
      
      {$region PathsList}
      _PathsListMenu := new System.Windows.Forms.ContextMenuStrip();
      
      var _PathsListMenuAddFolder   := new ToolStripMenuItem();
      _PathsListMenuAddFolder.Text  := 'Add folder'; 
      _PathsListMenuAddFolder.Image := Resources.Image('open.png');
      _PathsListMenuAddFolder.Click += (sender, e) ->
        begin
          var dialog := new FolderBrowserDialog();
          
          if dialog.ShowDialog() = System.Windows.Forms.DialogResult.OK then
            AddSourcePath(dialog.SelectedPath);
        end;
      _PathsListMenu.Items.Add(_PathsListMenuAddFolder);
      
      var _PathsListMenuClear   := new ToolStripMenuItem();
      _PathsListMenuClear.Text  := 'Clear'; 
      _PathsListMenuClear.Image := Resources.Image('clear.png');
      _PathsListMenuClear.Click += (sender, e) -> _PathsList.Clear();
      _PathsListMenu.Items.Add(_PathsListMenuClear);
      
      var _PathsListMenuCut   := new ToolStripMenuItem();
      _PathsListMenuCut.Text  := 'Cut'; 
      _PathsListMenuCut.Image := Resources.Image('cut.png');
      _PathsListMenuCut.Click += (sender, e) -> _PathsList.Cut();
      _PathsListMenu.Items.Add(_PathsListMenuCut);
      
      var _PathsListMenuCopy   := new ToolStripMenuItem();
      _PathsListMenuCopy.Text  := 'Copy'; 
      _PathsListMenuCopy.Image := Resources.Image('copy.png');
      _PathsListMenuCopy.Click += (sender, e) -> _PathsList.Copy();
      _PathsListMenu.Items.Add(_PathsListMenuCopy);
      
      var PathsListMenuPaste   := new ToolStripMenuItem();
      PathsListMenuPaste.Text  := 'Paste'; 
      PathsListMenuPaste.Image := Resources.Image('paste.png');
      PathsListMenuPaste.Click += (sender, e) -> _PathsList.Paste();
      _PathsListMenu.Items.Add(PathsListMenuPaste);
      
      var _PathsListDesc         := new &Label();
      _PathsListDesc.Location    := new Point(0, 0);
      _PathsListDesc.Size        := new System.Drawing.Size(_LeftContainer.Panel1.ClientSize.Width, 15);
      _PathsListDesc.Anchor      := AnchorStyles.Left or AnchorStyles.Top or AnchorStyles.Right;
      _PathsListDesc.BackColor   := BackColor;
      _PathsListDesc.Text        := 'Paths for search:';
      _LeftContainer.Panel1.Controls.Add(_PathsListDesc);
      
      _PathsList                  := new TextBox();
      _PathsList.Location         := new Point(0, _PathsListDesc.Height);
      _PathsList.Size             := new System.Drawing.Size(_PathsListDesc.Width, _LeftContainer.Panel1.ClientSize.Height - _PathsListDesc.Height);
      _PathsList.Anchor           := AnchorStyles.Left or AnchorStyles.Top or AnchorStyles.Right or AnchorStyles.Bottom;
      _PathsList.BorderStyle      := System.Windows.Forms.BorderStyle.FixedSingle;
      _PathsList.Multiline        := true;
      _PathsList.WordWrap         := false;
      _PathsList.Font             := new System.Drawing.Font('Consolas', 10, FontStyle.Regular, GraphicsUnit.Point);
      _PathsList.ContextMenuStrip := _PathsListMenu;
      _PathsList.MouseDown        += (sender, e) -> 
        begin
          if e.Button =  System.Windows.Forms.MouseButtons.Right then
            begin
              _PathsList.ContextMenuStrip.Items[1].Enabled := _PathsList.TextLength > 0;
              _PathsList.ContextMenuStrip.Items[2].Enabled := _PathsList.SelectionLength > 0;
              _PathsList.ContextMenuStrip.Items[3].Enabled := _PathsList.SelectionLength > 0;
            end;
        end;
      _PathsList.AllowDrop        := true;
      _PathsList.DragEnter        += (sender, e) -> begin e.Effect := DragDropEffects.All; end;
      _PathsList.DragDrop         += (sender, e) -> 
        begin
          var paths := e.Data.GetData(DataFormats.FileDrop) as PathsNames;
          
          foreach var path in paths do
            if Directory.Exists(path) then
              AddSourcePath(path);
        end;
      _LeftContainer.Panel1.Controls.Add(_PathsList);
      {$endregion}
      
      {$region FindFilters}
      _FindFiltersMenu := new System.Windows.Forms.ContextMenuStrip();

      var _FindFiltersMenuClear   := new ToolStripMenuItem();
      _FindFiltersMenuClear.Text  := 'Clear'; 
      _FindFiltersMenuClear.Image := Resources.Image('clear.png');
      _FindFiltersMenuClear.Click += (sender, e) -> _FindFilters.Clear();
      _FindFiltersMenu.Items.Add(_FindFiltersMenuClear);
      
      var _FindFiltersMenuCut   := new ToolStripMenuItem();
      _FindFiltersMenuCut.Text  := 'Cut'; 
      _FindFiltersMenuCut.Image := Resources.Image('cut.png');
      _FindFiltersMenuCut.Click += (sender, e) -> _FindFilters.Cut();
      _FindFiltersMenu.Items.Add(_FindFiltersMenuCut);
      
      var _FindFiltersMenuCopy   := new ToolStripMenuItem();
      _FindFiltersMenuCopy.Text  := 'Copy'; 
      _FindFiltersMenuCopy.Image := Resources.Image('copy.png');
      _FindFiltersMenuCopy.Click += (sender, e) -> _FindFilters.Copy();
      _FindFiltersMenu.Items.Add(_FindFiltersMenuCopy);
      
      var _FindFiltersMenuPaste   := new ToolStripMenuItem();
      _FindFiltersMenuPaste.Text  := 'Paste'; 
      _FindFiltersMenuPaste.Image := Resources.Image('paste.png');
      _FindFiltersMenuPaste.Click += (sender, e) -> _FindFilters.Paste();
      _FindFiltersMenu.Items.Add(_FindFiltersMenuPaste);
      
      var _FindFiltersDesc         := new &Label();
      _FindFiltersDesc.Location    := new Point(0, 0);
      _FindFiltersDesc.Size        := new System.Drawing.Size(_LeftContainer.Panel2.ClientSize.Width, 15);
      _FindFiltersDesc.Anchor      := AnchorStyles.Left or AnchorStyles.Top or AnchorStyles.Right;
      _FindFiltersDesc.BackColor   := BackColor;
      _FindFiltersDesc.Text        := 'Search filters:';
      _LeftContainer.Panel2.Controls.Add(_FindFiltersDesc);
      
      _FindFilters                  := new TextBox();
      _FindFilters.Location         := new Point(0, _FindFiltersDesc.Height);
      _FindFilters.Size             := new System.Drawing.Size(_FindFiltersDesc.Width, _LeftContainer.Panel2.ClientSize.Height - _FindFiltersDesc.Height);
      _FindFilters.Anchor           := AnchorStyles.Left or AnchorStyles.Top or AnchorStyles.Right or AnchorStyles.Bottom;
      _FindFilters.BorderStyle      := System.Windows.Forms.BorderStyle.FixedSingle;
      _FindFilters.Multiline        := true;
      _FindFilters.WordWrap         := false;
      _FindFilters.Font             := new System.Drawing.Font('Consolas', 10, FontStyle.Regular, GraphicsUnit.Point);
      _FindFilters.ContextMenuStrip := _FindFiltersMenu;
      _FindFilters.MouseDown        += (sender, e) -> 
        begin
          if e.Button =  System.Windows.Forms.MouseButtons.Right then
            begin
              _FindFilters.ContextMenuStrip.Items[0].Enabled := _FindFilters.TextLength > 0;
              _FindFilters.ContextMenuStrip.Items[1].Enabled := _FindFilters.SelectionLength > 0;
              _FindFilters.ContextMenuStrip.Items[2].Enabled := _FindFilters.SelectionLength > 0;
            end;
        end;
      _LeftContainer.Panel2.Controls.Add(_FindFilters);
      {$endregion}
      
      {$region Results}
      _ResultsMenu := new System.Windows.Forms.ContextMenuStrip();

      var _ResultsMenuClear   := new ToolStripMenuItem();
      _ResultsMenuClear.Text  := 'Clear'; 
      _ResultsMenuClear.Image := Resources.Image('clear.png');
      _ResultsMenuClear.Click += (sender, e) -> begin _Results.Nodes.Clear(); ResultMenuManageAbility(); end;
      _ResultsMenu.Items.Add(_ResultsMenuClear);
      
      var _ResultsMenuCut   := new ToolStripMenuItem();
      _ResultsMenuCut.Text  := 'Export'; 
      _ResultsMenuCut.Image := Resources.Image('save.png');
      _ResultsMenuCut.Click += SaveResultsClick;
      _ResultsMenu.Items.Add(_ResultsMenuCut);
      
      _ResultNodeMenu := new System.Windows.Forms.ContextMenuStrip();
       
      var _ResultNodeMenuCopy   := new ToolStripMenuItem();
      _ResultNodeMenuCopy.Text  := 'Copy'; 
      _ResultNodeMenuCopy.Image := Resources.Image('copy.png');
      _ResultNodeMenuCopy.Click += (sender, e) ->
        begin
          var node := _Results.SelectedNode;
          
          if node <> nil then
            begin
              var lines := '';
              
              if node.Level = 2 then
                lines := _Results.SelectedNode.Text
              else if node.Level = 1 then
                foreach var n: TreeNode in node.Nodes do
                  lines += n.Text + #13#10;
              
              if lines <> '' then
                Clipboard.SetText(lines);
            end;
        end;
      _ResultNodeMenu.Items.Add(_ResultNodeMenuCopy);
      
      var _ResultNodeMenuDel   := new ToolStripMenuItem();
      _ResultNodeMenuDel.Text  := 'Delete'; 
      _ResultNodeMenuDel.Image := Resources.Image('delete.png');
      _ResultNodeMenuDel.Click += (sender, e) ->
        begin
          var node := _Results.SelectedNode;
          
          if node <> nil then
            _Results.Nodes.Remove(node);
          
          ResultMenuManageAbility();
        end;
      _ResultNodeMenu.Items.Add(_ResultNodeMenuDel);
      
      var _ResultNodeMenuOpen   := new ToolStripMenuItem();
      _ResultNodeMenuOpen.Text  := 'Open file location'; 
      _ResultNodeMenuOpen.Image := Resources.Image('folder.png');
      _ResultNodeMenuOpen.Click += (sender, e) ->
        begin
          var node := _Results.SelectedNode;
          
          if (node <> nil) and (node.Level = 2) then
            begin
              var path := node.Text.Substring(0, node.Text.LastIndexOf('\'));
              
              try
                Process.Start('explorer', path);
              except on ex: Exception do
                Message.Error($'command "explorer {path}" execution error: {ex.Message}');
              end;
            end;
        end;
      _ResultNodeMenu.Items.Add(_ResultNodeMenuOpen);
      
      var _ImageList        := new ImageList();
      _ImageList.ColorDepth := ColorDepth.Depth32Bit;
      _ImageList.ImageSize  := new System.Drawing.Size(16, 16);
      _ImageList.Images.Add('find',   Resources.Image('find.png'));
      _ImageList.Images.Add('error',  Resources.Image('error.png'));
      _ImageList.Images.Add('folder', Resources.Image('folder.png'));
      _ImageList.Images.Add('file',   Resources.Image('file.png'));
      
      var _ResultsDesc         := new &Label();
      _ResultsDesc.Location    := new Point(0, 0);
      _ResultsDesc.Size        := new System.Drawing.Size(_MainContainer.Panel2.ClientSize.Width, 15);
      _ResultsDesc.Anchor      := AnchorStyles.Left or AnchorStyles.Top or AnchorStyles.Right;
      _ResultsDesc.BackColor   := BackColor;
      _ResultsDesc.Text        := 'Search results:';
      _MainContainer.Panel2.Controls.Add(_ResultsDesc);
      
      _Results                  := new TreeView();
      _Results.Location         := new Point(0, _ResultsDesc.Height);
      _Results.Size             := new System.Drawing.Size(_ResultsDesc.Width, _MainContainer.Panel2.ClientSize.Height - _ResultsDesc.Height);
      _Results.Anchor           := AnchorStyles.Left or AnchorStyles.Top or AnchorStyles.Right or AnchorStyles.Bottom;
      _Results.BorderStyle      := System.Windows.Forms.BorderStyle.FixedSingle;
      _Results.Font             := new System.Drawing.Font('Consolas', 10, FontStyle.Regular, GraphicsUnit.Point);
      _Results.ItemHeight       := 18;
      _Results.ImageList        := _ImageList;
      _Results.ContextMenuStrip := _ResultsMenu;
      _Results.ShowRootLines    := true;
      _Results.ShowPlusMinus    := true;
      _Results.Scrollable       := true;
      _Results.ShowNodeToolTips := true;
      _Results.MouseClick       += (sender, e) ->
        begin
          if e.Button = System.Windows.Forms.MouseButtons.Right then
            begin
              _Results.SelectedNode := _Results.GetNodeAt(e.Location);
              
              var exp := (_Results.SelectedNode <> nil) and (_Results.SelectedNode.Level = 2);
              
              _ResultNodeMenu.Items[0].Visible := exp or (_Results.SelectedNode.Nodes.Count > 0);
              _ResultNodeMenu.Items[2].Visible := exp and (_Results.SelectedNode.ForeColor <> Color.Red);
            end;
        end;
      _MainContainer.Panel2.Controls.Add(_Results);
      {$endregion}
      
      {$region ActionsBox}
      _ActionsBox          := new Panel();
      _ActionsBox.Location := new Point(0, _MainContainer.Top + _MainContainer.Height + 1);
      _ActionsBox.Size     := new System.Drawing.Size(ClientSize.Width, 26);
      _ActionsBox.Anchor   := AnchorStyles.Left or AnchorStyles.Right or AnchorStyles.Bottom;
      
      _SaveResults            := new Button();
      _SaveResults.Size       := new System.Drawing.Size(75, 24);
      _SaveResults.Location   := new Point(_ActionsBox.Width - _SaveResults.Width - 2, 2);
      _SaveResults.Anchor     := AnchorStyles.Bottom or AnchorStyles.Right;
      _SaveResults.Text       := '    Export';
      _SaveResults.Image      := Resources.Image('save.png');
      _SaveResults.ImageAlign := ContentAlignment.MiddleLeft;
      _SaveResults.Click      += SaveResultsClick;
      _ActionsBox.Controls.Add(_SaveResults);
      
      _FindButton          := new Button();
      _FindButton.Size     := new System.Drawing.Size(_SaveResults.Width, _SaveResults.Height);
      _FindButton.Location := new Point(_SaveResults.Left - _FindButton.Width - 5, _SaveResults.Top);
      _FindButton.Anchor   := AnchorStyles.Bottom or AnchorStyles.Right;
      _FindButton.Text     := 'Find';
      _FindButton.Click    += FindButtonClick;
      _ActionsBox.Controls.Add(_FindButton);
      
      _SearchProgress          := new ProgressBar();
      _SearchProgress.Location := new Point(3, _SaveResults.Top + 1);
      _SearchProgress.Size     := new System.Drawing.Size(_FindButton.Left - 5 - 3, _SaveResults.Height - 2);
      _SearchProgress.Anchor   := AnchorStyles.Left or AnchorStyles.Right or AnchorStyles.Bottom;
      _ActionsBox.Controls.Add(_SearchProgress);
      {$endregion}
      
      {$region StatusBar}
      _StatusBar             := new StatusStrip();
      _StatusBar.Dock        := DockStyle.Bottom;
      _StatusBar.SizingGrip  := false;
      _StatusBar.LayoutStyle := ToolStripLayoutStyle.HorizontalStackWithOverflow;
      
      _ElapsedInfo              := new ToolStripStatusLabel();
      _ElapsedInfo.DisplayStyle := ToolStripItemDisplayStyle.Text;
      _ElapsedInfo.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Regular);
      _ElapsedInfo.Alignment    := ToolStripItemAlignment.Left;
      _ElapsedInfo.TextAlign    := ContentAlignment.MiddleLeft;
      _StatusBar.Items.Add(_ElapsedInfo);
      
      var _Sep1Info          := new ToolStripStatusLabel();
      _Sep1Info.DisplayStyle := ToolStripItemDisplayStyle.Text;
      _Sep1Info.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Bold);
      _Sep1Info.Alignment    := ToolStripItemAlignment.Left;
      _Sep1Info.TextAlign    := ContentAlignment.MiddleCenter;
      _Sep1Info.ForeColor    := Color.Gray;
      _Sep1Info.Text         := '|';
      _StatusBar.Items.Add(_Sep1Info);
      
      _RemainingInfo              := new ToolStripStatusLabel();
      _RemainingInfo.DisplayStyle := ToolStripItemDisplayStyle.Text;
      _RemainingInfo.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Regular);
      _RemainingInfo.Alignment    := ToolStripItemAlignment.Left;
      _RemainingInfo.TextAlign    := ContentAlignment.MiddleLeft;
      _StatusBar.Items.Add(_RemainingInfo);
      
      var _Sep2Info          := new ToolStripStatusLabel();
      _Sep2Info.DisplayStyle := ToolStripItemDisplayStyle.Text;
      _Sep2Info.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Bold);
      _Sep2Info.Alignment    := ToolStripItemAlignment.Left;
      _Sep2Info.TextAlign    := ContentAlignment.MiddleCenter;
      _Sep2Info.ForeColor    := Color.Gray;
      _Sep2Info.Text         := '|';
      _StatusBar.Items.Add(_Sep2Info);
      
      _FilesCountInfo              := new ToolStripStatusLabel();
      _FilesCountInfo.DisplayStyle := ToolStripItemDisplayStyle.Text;
      _FilesCountInfo.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Regular);
      _FilesCountInfo.Alignment    := ToolStripItemAlignment.Left;
      _FilesCountInfo.TextAlign    := ContentAlignment.MiddleLeft;
      _StatusBar.Items.Add(_FilesCountInfo);
      
      var _Sep3Info          := new ToolStripStatusLabel();
      _Sep3Info.DisplayStyle := ToolStripItemDisplayStyle.Text;
      _Sep3Info.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Bold);
      _Sep3Info.Alignment    := ToolStripItemAlignment.Left;
      _Sep3Info.TextAlign    := ContentAlignment.MiddleCenter;
      _Sep3Info.ForeColor    := Color.Gray;
      _Sep3Info.Text         := '|';
      _StatusBar.Items.Add(_Sep3Info);
      
      _StageInfo              := new ToolStripStatusLabel();
      _StageInfo.DisplayStyle := ToolStripItemDisplayStyle.Text;
      _StageInfo.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Regular);
      _StageInfo.Alignment    := ToolStripItemAlignment.Left;
      _StageInfo.TextAlign    := ContentAlignment.MiddleLeft;
      _StatusBar.Items.Add(_StageInfo);
      {$endregion}
      
      {$region AddControls}
      Controls.Add(_MainContainer);
      Controls.Add(_ActionsBox);
      Controls.Add(_StatusBar);
      {$endregion}
      
      {$region Init}
      _ProgressTimer         := new System.Timers.Timer();
      _ProgressTimer.Enabled := false;
      
      ResultMenuManageAbility();
      
      _ElapsedInfo.Text     := 'Elapsed: -:--:--';
      _RemainingInfo.Text   := 'Remaining: -:--:--';
      _FilesCountInfo.Text  := 'Files: -/-';
      {$endregion}
    end;
    {$endregion}
  end;


end.