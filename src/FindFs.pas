{$apptype windows}

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
{$resource res\file.png}
{$resource res\folder.png}
{$resource res\error.png}

{$mainresource res\res.res}


uses
  System,
  System.IO,
  System.Text,
  System.Text.RegularExpressions,
  System.Globalization,
  System.Threading,
  System.Threading.Tasks,
  System.Diagnostics,
  System.Drawing,
  System.Windows.Forms;


type
  PathsNames = array of string;
  
  MainForm = class(Form)
  private
    {$region Fields}
    _MainContainer     : SplitContainer;
    _LeftContainer     : SplitContainer;
    _PathsListMenu     : System.Windows.Forms.ContextMenuStrip;
    _PathsList         : TextBox;
    _FindFiltersMenu   : System.Windows.Forms.ContextMenuStrip;
    _FindFilters       : TextBox;
    _ResultsMenu       : System.Windows.Forms.ContextMenuStrip;
    _ResultNodeMenu    : System.Windows.Forms.ContextMenuStrip;
    _Results           : TreeView;
    _ActionsBox        : Panel;
    _FindButton        : Button;
    _SaveResults       : Button;
    _SearchProgress    : ProgressBar;
    _StatusBar         : StatusStrip;
    _ElapsedInfo       : ToolStripStatusLabel;
    _RemainingInfo     : ToolStripStatusLabel;
    _FilesCountInfo    : ToolStripStatusLabel;
    _StageInfo         : ToolStripStatusLabel;
    _TimerUpdateInfo   : System.Timers.Timer;
    _StartTime         : DateTime;
    _TotalFilesCount   : integer;
    _CompletedFiles    : integer;
    _TotalFiltersCount : integer;
    _CompletedFilters  : integer;
    _FindAbort         : boolean;
    {$endregion}
    
    {$region Handlers}
    procedure FindButtonClick(sender: object; e: EventArgs);
    begin
      if _FindButton.Text = 'Find' then
        begin
          var paths   := _pathsList.Lines;
          var filters := _FindFilters.Lines;
          
          _FindButton.Enabled := false;
          _FindAbort          := false;
          Task.Factory.StartNew(() -> begin FindTask(paths, filters); end);
        end
      else
        begin
          _FindButton.Enabled := false;
          _FindAbort          := true;
        end;
    end;
    
    procedure SaveResultsClick(sender: object; e: EventArgs);
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
    procedure ResultMenuManageAbility();
    begin
      _SaveResults.Enabled          := _Results.Nodes.Count > 0;
      _ResultsMenu.Items[0].Enabled := _SaveResults.Enabled;
      _ResultsMenu.Items[1].Enabled := _SaveResults.Enabled;
    end;
    
    procedure AddSourcePath(path: string);
    begin
      var lines := _PathsList.Text;
          
      if lines.Length > 0 then
        lines := lines.TrimEnd(#13, #10) + #13#10;
          
      _PathsList.Text := lines + path;
    end;
    
    procedure BuildLinearFilesList(path: string; FilesList, ErrorList: List<string>);
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
            foreach var f: string in files do
              FilesList.Add(f);
        end;
    end;
    
    procedure UpdateInfo();
    begin
      var progress := _TotalFilesCount * _CompletedFilters + _CompletedFiles;
      var total    := _TotalFilesCount * _TotalFiltersCount;
      var dt       := DateTime.Now - _StartTime;
      
      var percent := Convert.ToInt32(100.0 * progress / total);
      if percent > _SearchProgress.Value then
        _SearchProgress.Value := percent;
      
      var v := progress / dt.Ticks;
      var t := new TimeSpan(Convert.ToInt64((total - progress) / v));
      if t.TotalSeconds <= 0 then
        t := new TimeSpan(0, 0, 10);
      
      _ElapsedInfo.Text    := $'Elapsed: {dt.Hours}:{dt.Minutes:d2}:{dt.Seconds:d2}';
      _RemainingInfo.Text  := $'Remaining: {t.Hours}:{t.Minutes:d2}:{t.Seconds:d2}';
      _FilesCountInfo.Text := $'Files: {_CompletedFiles}/{_TotalFilesCount}';
    end;
    
    procedure FindTask(paths, filters: array of string);
    begin
      Invoke(() ->
        begin
          _SearchProgress.Value := 0;
          _ElapsedInfo.Text     := 'Elapsed: 0:00:00';
          _RemainingInfo.Text   := 'Remaining: -:--:--';
          _FilesCountInfo.Text  := 'Files: -/-';
          _StageInfo.Text       := 'Create files list ...';
          _Results.Nodes.Clear();
          _FindButton.Text      := 'Abort';
          _FindButton.Enabled   := true;
          Cursor                := Cursors.WaitCursor;
        end
      );
      
      var files  := new List<string>();
      var errors := new List<string>();
      
      foreach var path: string in paths do
        BuildLinearFilesList(path, files, errors);
      
      if not _FindAbort then
        begin
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
              
              Invoke(() -> begin _Results.Nodes.Add(ErrorsNode); end);
            end;
          
          Invoke(() ->
            begin
              Cursor                := Cursors.Default;
              _FilesCountInfo.Text  := $'Files: 0/{files.Count}';
              _StageInfo.Text       := $'Apply filters: 0/{filters.Length}';
            end
          );
          
          _TotalFilesCount   := files.Count;
          _TotalFiltersCount := filters.Length;
          _CompletedFilters  := 0;
          _StartTime         := DateTime.Now;
          _TimerUpdateInfo.Enabled := true;
          _TimerUpdateInfo.Start();
          
          foreach var filter: string in filters do
            begin
              _CompletedFiles := 0;
              
              Invoke(() -> begin _FilesCountInfo.Text := $'Files: 0/{files.Count}'; end);
              
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
                    
                    _CompletedFiles += 1;
                    
                    if _FindAbort then
                      break;
                  end;
              except on ex: Exception do
                regerr := ex.Message;
              end;
              
              _CompletedFilters += 1;
              
              Invoke(() -> begin _StageInfo.Text := $'Apply filters: {_CompletedFilters}/{filters.Length}'; end);
              
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
                        var node              := new TreeNode();
                        node.Text             := line;
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
              
              Invoke(() -> begin _Results.Nodes.Add(FilterNode); end);
              
              if _FindAbort then
                break;
            end;
        end
      else
        Invoke(() -> begin Cursor := Cursors.Default; end);
      
      _TimerUpdateInfo.Stop();
      _TimerUpdateInfo.Enabled := false;
      
      if not _FindAbort then
        Invoke(() ->
          begin
            _SearchProgress.Value := 100;
            _RemainingInfo.Text   := 'Remaining: 0:00:00';
            _FilesCountInfo.Text  := $'Files: {_CompletedFiles}/{files.Count}';
            _StageInfo.Text       := $'Apply filters: {_CompletedFilters}/{filters.Length}';
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
  public
    constructor ();
    begin
      {$region MainForm}
      ClientSize    := new System.Drawing.Size(500, 500);
      MinimumSize   := Size;
      Icon          := new System.Drawing.Icon(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('icon.ico'));
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
      
      var PathsListMenuAddFolder   := new ToolStripMenuItem();
      PathsListMenuAddFolder.Text  := 'Add folder'; 
      PathsListMenuAddFolder.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('open.png'));
      PathsListMenuAddFolder.Click += (sender, e) ->
        begin
          var dialog := new FolderBrowserDialog();
          
          if dialog.ShowDialog() = System.Windows.Forms.DialogResult.OK then
            AddSourcePath(dialog.SelectedPath);
        end;
      _PathsListMenu.Items.Add(PathsListMenuAddFolder);
      
      var PathsListMenuClear   := new ToolStripMenuItem();
      PathsListMenuClear.Text  := 'Clear'; 
      PathsListMenuClear.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('clear.png'));
      PathsListMenuClear.Click += (sender, e) -> begin _PathsList.Clear(); end;
      _PathsListMenu.Items.Add(PathsListMenuClear);
      
      var PathsListMenuCut   := new ToolStripMenuItem();
      PathsListMenuCut.Text  := 'Cut'; 
      PathsListMenuCut.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('cut.png'));
      PathsListMenuCut.Click += (sender, e) -> begin _PathsList.Cut(); end;
      _PathsListMenu.Items.Add(PathsListMenuCut);
      
      var PathsListMenuCopy   := new ToolStripMenuItem();
      PathsListMenuCopy.Text  := 'Copy'; 
      PathsListMenuCopy.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('copy.png'));
      PathsListMenuCopy.Click += (sender, e) -> begin _PathsList.Copy(); end;
      _PathsListMenu.Items.Add(PathsListMenuCopy);
      
      var PathsListMenuPaste   := new ToolStripMenuItem();
      PathsListMenuPaste.Text  := 'Paste'; 
      PathsListMenuPaste.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('paste.png'));
      PathsListMenuPaste.Click += (sender, e) -> begin _PathsList.Paste(); end;
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
          var paths := PathsNames(e.Data.GetData(DataFormats.FileDrop));
          
          foreach var path in paths do
            if Directory.Exists(path) then
              AddSourcePath(path);
        end;
      _LeftContainer.Panel1.Controls.Add(_PathsList);
      {$endregion}
      
      {$region FindFilters}
      _FindFiltersMenu := new System.Windows.Forms.ContextMenuStrip();

      var FindFiltersMenuClear   := new ToolStripMenuItem();
      FindFiltersMenuClear.Text  := 'Clear'; 
      FindFiltersMenuClear.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('clear.png'));
      FindFiltersMenuClear.Click += (sender, e) -> begin _FindFilters.Clear(); end;
      _FindFiltersMenu.Items.Add(FindFiltersMenuClear);
      
      var FindFiltersMenuCut   := new ToolStripMenuItem();
      FindFiltersMenuCut.Text  := 'Cut'; 
      FindFiltersMenuCut.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('cut.png'));
      FindFiltersMenuCut.Click += (sender, e) -> begin _FindFilters.Cut(); end;
      _FindFiltersMenu.Items.Add(FindFiltersMenuCut);
      
      var FindFiltersMenuCopy   := new ToolStripMenuItem();
      FindFiltersMenuCopy.Text  := 'Copy'; 
      FindFiltersMenuCopy.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('copy.png'));
      FindFiltersMenuCopy.Click += (sender, e) -> begin _FindFilters.Copy(); end;
      _FindFiltersMenu.Items.Add(FindFiltersMenuCopy);
      
      var FindFiltersMenuPaste   := new ToolStripMenuItem();
      FindFiltersMenuPaste.Text  := 'Paste'; 
      FindFiltersMenuPaste.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('paste.png'));
      FindFiltersMenuPaste.Click += (sender, e) -> begin _FindFilters.Paste(); end;
      _FindFiltersMenu.Items.Add(FindFiltersMenuPaste);
      
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

      var ResultsMenuClear   := new ToolStripMenuItem();
      ResultsMenuClear.Text  := 'Clear'; 
      ResultsMenuClear.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('clear.png'));
      ResultsMenuClear.Click += (sender, e) -> begin _Results.Nodes.Clear(); ResultMenuManageAbility(); end;
      _ResultsMenu.Items.Add(ResultsMenuClear);
      
      var ResultsMenuCut   := new ToolStripMenuItem();
      ResultsMenuCut.Text  := 'Export'; 
      ResultsMenuCut.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('save.png'));
      ResultsMenuCut.Click += SaveResultsClick;
      _ResultsMenu.Items.Add(ResultsMenuCut);
      
      _ResultNodeMenu := new System.Windows.Forms.ContextMenuStrip();
       
      var ResultNodeMenuCopy   := new ToolStripMenuItem();
      ResultNodeMenuCopy.Text  := 'Copy'; 
      ResultNodeMenuCopy.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('copy.png'));
      ResultNodeMenuCopy.Click += (sender, e) ->
        begin
          var node := _Results.SelectedNode;
          
          if node <> nil then
            begin
              var lines := '';
              
              if node.Level = 1 then
                lines := _Results.SelectedNode.Text
              else if node.Level = 0 then
                foreach var n: TreeNode in node.Nodes do
                  lines += n.Text + #13#10;
              
              Clipboard.SetText(lines);
            end;
        end;
      _ResultNodeMenu.Items.Add(ResultNodeMenuCopy);
      
      var ResultNodeMenuDel   := new ToolStripMenuItem();
      ResultNodeMenuDel.Text  := 'Delete'; 
      ResultNodeMenuDel.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('delete.png'));
      ResultNodeMenuDel.Click += (sender, e) ->
        begin
          var node := _Results.SelectedNode;
          
          if node <> nil then
            _Results.Nodes.Remove(node);
          
          ResultMenuManageAbility();
        end;
      _ResultNodeMenu.Items.Add(ResultNodeMenuDel);
      
      var ResultNodeMenuOpen   := new ToolStripMenuItem();
      ResultNodeMenuOpen.Text  := 'Open file location'; 
      ResultNodeMenuOpen.Image := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('folder.png'));
      ResultNodeMenuOpen.Click += (sender, e) ->
        begin
          var node := _Results.SelectedNode;
          
          if (node <> nil) and (node.Level = 1) then
            begin
              var path := node.Text.Substring(0, node.Text.LastIndexOf('\'));
              
              try
                Process.Start('explorer', path);
              except on ex: Exception do
                MessageBox.Show($'command "explorer {path}" execution error: {ex.Message}', 
                                'Error', MessageBoxButtons.OK, MessageBoxIcon.Error);
              end;
            end;
        end;
      _ResultNodeMenu.Items.Add(ResultNodeMenuOpen);
      
      var ImgList        := new ImageList();
      ImgList.ColorDepth := ColorDepth.Depth32Bit;
      ImgList.ImageSize  := new System.Drawing.Size(16, 16);
      ImgList.Images.Add('folder', Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('folder.png')));
      ImgList.Images.Add('file', Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('file.png')));
      ImgList.Images.Add('error', Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('error.png')));
      
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
      _Results.ImageList        := ImgList;
      _Results.ContextMenuStrip := _ResultsMenu;
      _Results.ShowRootLines    := true;
      _Results.ShowPlusMinus    := true;
      _Results.Scrollable       := true;
      _Results.ShowNodeToolTips := true;
      _Results.MouseClick       += (sender, e) ->
        begin
          if e.Button = System.Windows.Forms.MouseButtons.Right then
            begin
              _Results.SelectedNode            := _Results.GetNodeAt(e.Location);
              _ResultNodeMenu.Items[2].Enabled := _Results.SelectedNode.Level = 1;
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
      _SaveResults.Image      := Image.FromStream(System.Reflection.Assembly.GetEntryAssembly().GetManifestResourceStream('save.png'));
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
      
      var Sep1Info          := new ToolStripStatusLabel();
      Sep1Info.DisplayStyle := ToolStripItemDisplayStyle.Text;
      Sep1Info.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Bold);
      Sep1Info.Alignment    := ToolStripItemAlignment.Left;
      Sep1Info.TextAlign    := ContentAlignment.MiddleCenter;
      Sep1Info.ForeColor    := Color.Gray;
      Sep1Info.Text         := '|';
      _StatusBar.Items.Add(Sep1Info);
      
      _RemainingInfo              := new ToolStripStatusLabel();
      _RemainingInfo.DisplayStyle := ToolStripItemDisplayStyle.Text;
      _RemainingInfo.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Regular);
      _RemainingInfo.Alignment    := ToolStripItemAlignment.Left;
      _RemainingInfo.TextAlign    := ContentAlignment.MiddleLeft;
      _StatusBar.Items.Add(_RemainingInfo);
      
      var Sep2Info          := new ToolStripStatusLabel();
      Sep2Info.DisplayStyle := ToolStripItemDisplayStyle.Text;
      Sep2Info.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Bold);
      Sep2Info.Alignment    := ToolStripItemAlignment.Left;
      Sep2Info.TextAlign    := ContentAlignment.MiddleCenter;
      Sep2Info.ForeColor    := Color.Gray;
      Sep2Info.Text         := '|';
      _StatusBar.Items.Add(Sep2Info);
      
      _FilesCountInfo              := new ToolStripStatusLabel();
      _FilesCountInfo.DisplayStyle := ToolStripItemDisplayStyle.Text;
      _FilesCountInfo.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Regular);
      _FilesCountInfo.Alignment    := ToolStripItemAlignment.Left;
      _FilesCountInfo.TextAlign    := ContentAlignment.MiddleLeft;
      _StatusBar.Items.Add(_FilesCountInfo);
      
      var Sep3Info          := new ToolStripStatusLabel();
      Sep3Info.DisplayStyle := ToolStripItemDisplayStyle.Text;
      Sep3Info.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Bold);
      Sep3Info.Alignment    := ToolStripItemAlignment.Left;
      Sep3Info.TextAlign    := ContentAlignment.MiddleCenter;
      Sep3Info.ForeColor    := Color.Gray;
      Sep3Info.Text         := '|';
      _StatusBar.Items.Add(Sep3Info);
      
      _StageInfo              := new ToolStripStatusLabel();
      _StageInfo.DisplayStyle := ToolStripItemDisplayStyle.Text;
      _StageInfo.Font         := new System.Drawing.Font('Segoe UI', 9.0, System.Drawing.FontStyle.Regular);
      _StageInfo.Alignment    := ToolStripItemAlignment.Left;
      _StageInfo.TextAlign    := ContentAlignment.MiddleLeft;
      _StatusBar.Items.Add(_StageInfo);
      
      _TimerUpdateInfo          := new System.Timers.Timer();
      _TimerUpdateInfo.Interval := 1000.0;
      _TimerUpdateInfo.Enabled  := false;
      _TimerUpdateInfo.Elapsed  += (sender, e) -> begin UpdateInfo(); end;
      {$endregion}
      
      {$region AddControls}
      Controls.Add(_MainContainer);
      Controls.Add(_ActionsBox);
      Controls.Add(_StatusBar);
      {$endregion}
      
      {$region Init}
      ResultMenuManageAbility();
      
      _ElapsedInfo.Text     := 'Elapsed: -:--:--';
      _RemainingInfo.Text   := 'Remaining: -:--:--';
      _FilesCountInfo.Text  := 'Files: -/-';
      {$endregion}
    end;
  end;


begin
  Application.CurrentInputLanguage := InputLanguage.FromCulture(new CultureInfo('en-US'));
  Application.EnableVisualStyles();
  Application.SetCompatibleTextRenderingDefault(false);
  Application.Run(new MainForm());
end.