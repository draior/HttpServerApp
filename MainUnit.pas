unit MainUnit;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, IdBaseComponent, IdComponent,
  IdCustomTCPServer, IdCustomHTTPServer, IdHTTPServer, IdContext, Vcl.Menus,
  Vcl.ExtCtrls, Data.DB, Data.Win.ADODB, System.JSON, System.UITypes,
  MSjanXMLParser, Vcl.Grids, Vcl.DBGrids, RxDBCtrl, Vcl.ComCtrls, Vcl.ImgList;

type
  TfMain = class(TForm)
    bbStart: TButton;
    bbStop: TButton;
    bbActiveConnection: TButton;
    bbExit: TButton;
    pc: TPageControl;
    tsLog: TTabSheet;
    HTTPSrv: TIdHTTPServer;
    pm: TPopupMenu;
    miRestore: TMenuItem;
    miExit: TMenuItem;
    m: TMemo;
    JSonImport: TTimer;
    Database: TADOConnection;
    TrayIcon: TTrayIcon;
    ImageList: TImageList;
    tStart: TTimer;
    qr: TADOQuery;
    sp: TADOStoredProc;
    procedure FormCreate(Sender: TObject);
    procedure HTTPSrvCommandGet(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure bbStartClick(Sender: TObject);
    procedure bbStopClick(Sender: TObject);
    procedure bbExitClick(Sender: TObject);
    procedure JSonImportTimer(Sender: TObject);
    procedure HTTPSrvDoneWithPostStream(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; var VCanFree: Boolean);
    procedure FormDestroy(Sender: TObject);
    procedure miExitClick(Sender: TObject);
    procedure TrayIconDblClick(Sender: TObject);
    procedure tStartTimer(Sender: TObject);
    procedure DatabaseAfterConnect(Sender: TObject);
  protected
    RequestCnt: Integer;
    procedure ConnectDB;
  private
    { Private declarations }
    Stoping: Boolean;
    ADate: TDateTime;
    
    procedure ProcessJsonFolder(Fld: String);
    procedure OnMinimize(Sender: TObject);
    procedure Log(Msg: String);
    function ProcessJsonToDB(JSONStr, FName: String): Boolean;
    function GetArticles: String;
    function CheckStatus: String;
    function GetRequestCnt: String;
    function HTTPRcvText(ARequestInfo: TIdHTTPRequestInfo; var ErrMsg: AnsiString): AnsiString;
    function GetFileList(const Dir, Mask: String; InclPath: Boolean; InclDirs: Boolean=True; RemoveExt: Boolean=False): TStringList; //VER
    function MinInteger(A, B: Integer): Integer;
    function SaveRcv(v: String): String;
    function SetCommandText(Qry: TADOQuery; const CmdStr: String; SetOpen: Boolean=True): Integer;
    function GetValue(obj: TJSONObject; Name: String): String;
 public
    { Public declarations }
  end;

var
  fMain: TfMain;

implementation

uses
  FmxUtils, ActiveX, synachar, IdGlobal, FileUtil, FileCtrl, DateUtils, RxMemDS,
  SysUnit, JsonSale, ULogUtils;

{$R *.dfm}

const
  tcpPort = 19898;
  JsonFolder = 'C:\Temp\WWWSales\';
  MaxReadBlockSize = 8192;
  DocType = 1;

procedure TfMain.bbExitClick(Sender: TObject);
begin
  if MessageDlg('Confirm Exit?', mtConfirmation, [mbYes, mbNo], 0) = mrNo then
    Exit;
  bbStopClick(nil);
  SleepEx(2000, False);
  Stoping := True;
  while not JSonImport.Enabled do begin
    SleepEx(250, False);
    Application.ProcessMessages;
  end;
  miExitClick(miExit);
end;

procedure TfMain.bbStartClick(Sender: TObject);
begin
  try
    HTTPSrv.Active := True;
    bbStart.Enabled := False;
    bbStop.Enabled := True;
    m.Lines.Insert(0, DateTimeToStr(Now) + ' server started! ');
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOk], 0);
  end;
end;

procedure TfMain.bbStopClick(Sender: TObject);
begin
  try
    HTTPSrv.Active := False;
    bbStart.Enabled := True;
    bbStop.Enabled := False;
    m.Lines.Insert(0, DateTimeToStr(Now)+ ' server stoped!');
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOk], 0);
  end;
end;

function TfMain.CheckStatus: String;
begin
  Result := '';
  try
    if SetCommandText(qr, 'select @@SPID') = 0 then
      Result := qr.Fields[0].AsString;
  except
    on E: Exception do
      Log('?? ' + DateTimeToStr(Now) + ' [CheckStatus] ' + E.Message);
  end;
end;

procedure TfMain.ConnectDB;
begin
  if not DataBase.Connected then begin
    DataBase.ConnectionString := 'FILE NAME=' + ExtractFileDir(Application.ExeName) + '\KAMI.udl';
    DataBase.Open;
  end;
end;

procedure TfMain.DatabaseAfterConnect(Sender: TObject);
begin
try
    TADOConnection(Sender).Execute('SET TRANSACTION ISOLATION LEVEL READ COMMITTED');
    TADOConnection(Sender).Execute('SET XACT_ABORT OFF');
    TADOConnection(Sender).Execute('SET NOCOUNT ON');
    TADOConnection(Sender).Execute('SET DATEFORMAT dmy');
    TADOConnection(Sender).Execute('SET DEADLOCK_PRIORITY NORMAL');
  except
    on E: Exception do
      Log('?? DatabaseAfterConnect: ' + E.Message);
  end;
end;

procedure TfMain.FormCreate(Sender: TObject);
begin
  try
    FormatSettings.DecimalSeparator := '.';
    FormatSettings.DateSeparator := '.';
    FormatSettings.ShortDateFormat := 'dd.mm.yyyy';
    RequestCnt := -1;

    HTTPSrv.DefaultPort := tcpPort;
    HTTPSrv.Bindings.Add.Port := tcpPort;

    pc.ActivePageindex := 0;

    bbStart.OnClick(bbStart);

    if not FileCtrl.ForceDirectories(JsonFolder + 'Imported\') then
      raise Exception.Create('Cannot create folder: ' + JsonFolder + 'Imported\');
    if not FileCtrl.ForceDirectories(JsonFolder + 'Error\') then
      raise Exception.Create('Cannot create folder: ' + JsonFolder + 'Error\');

    ADate := Trunc(Now);
    Stoping := False;

    ConnectDB;
    JSonImport.Enabled := True;
  except
    on E: Exception do
      MessageDlg(E.Message, mtError, [mbOk], 0);
  end;

  Application.OnMinimize := OnMinimize;

  tStart.Enabled := True;
end;

procedure TfMain.FormDestroy(Sender: TObject);
begin
  if Database.Connected then
    Database.Connected := False;
end;

function TfMain.GetArticles: String;
var
  X: TXMLFile;
  D, N: TXMLNode;
  i: Integer;
  q: TADOQuery;
  ADB: TAdoConnection;
begin
  X := TXMLFile.Create('Articles', '', 'windows-1251');
  //X.Encoding := '"utf-8"';
  try
    q := TADOQuery.Create(nil);
    q.Connection := ADB;

    q.SQL.Text := 'select ' +
                  '  Code, ' +
                  '  Name, ' +
                  '  IsNull(Category, '''') AvnCode, ' +
                  '  IsNull(ShortName, '''') AvnName, ' +
                  '  IsNull(CatCode, '''') AvnFreeCode, ' +
                  '  IsNull(invoice_name, '''') AvnFreeName ' +
                  'from Items with(nolock) where ID>100 and Used<>0 and IsGroup=0' ;
    q.Open;
    q.First;
    while not q.Eof do begin
      D := X.RootNode.AddChildByName('Article');
      for i := 0 to q.FieldCount-1 do begin
        N := D.AddChildByName(q.Fields[i].FieldName);
        if q.Fields[i].DataType = ftDate then
          N.Text := DateToStr(q.Fields[i].Value)
        else
          N.Text := q.Fields[i].Value;
      end;

      q.Next;
    end;

    Result := X.xmlAnsi; //, 'windows-1251', 'utf-8', [rfReplaceAll, rfIgnoreCase]);
  except
    on E: Exception do
      Result := '[srv.GetArticles] ' + E.Message;
  end;
  FreeAndNil(X);
  FreeAndNil(q);
  FreeAndNil(ADB);
end;

function TfMain.GetRequestCnt: String;
begin
  Result := IntToStr(RequestCnt);
  RequestCnt := -1;
end;

function TfMain.GetValue(obj: TJSONObject; Name: String): String;
var
  v: TJSONValue;
begin
  Result := '';
  v := obj.GetValue(Name);
  if v <> nil then
    Result := v.Value;
end;

function TfMain.HTTPRcvText(ARequestInfo: TIdHTTPRequestInfo; var ErrMsg: AnsiString): AnsiString;
var
  MemoryStream: TMemoryStream;
  BufferStr: AnsiString;
  RSize, ReadedBytes, ByteToRead: Integer;
  Buffer: PAnsiChar;
begin
  Result := '';
  if ARequestInfo.PostStream = nil then
    Exit;

  MemoryStream := TMemoryStream.Create;
  try
    MemoryStream.LoadFromStream(ARequestInfo.PostStream);
    ByteToRead := ARequestInfo.ContentLength;

    while ByteToRead > 0 do begin
      RSize := MaxReadBlockSize;
      if RSize > ByteToRead then
        RSize := ByteToRead;
      GetMem(Buffer, RSize);
      try
        ReadedBytes := MemoryStream.Read(Buffer^, RSize);
        SetString(BufferStr, Buffer, ReadedBytes);
        Result := Result + BufferStr;
      finally
        FreeMem(Buffer, RSize);
      end;
      ByteToRead := ARequestInfo.ContentLength - Length(Result);
    end;

  except
    on E: Exception do
      ErrMsg := E.Message;
  end;
  MemoryStream.Free;
end;

procedure TfMain.HTTPSrvCommandGet(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
var
  Rcv, S, Doc: String;
  L: TStringList;
  p: Integer;
  Err: AnsiString;
begin
  L := TStringList.Create;
  try
    CoInitialize(nil);
    RequestCnt := RequestCnt + 1;
    Doc := ARequestInfo.Document;
    p := Pos('/', Doc);
    if p <> 0 then
      Delete(Doc, p, 1);
    Rcv := HTTPRcvText(ARequestInfo, Err);
    L.Text := StringReplace(ARequestInfo.UnparsedParams, '&', #13#10, [rfIgnoreCase, rfReplaceAll]);

    AResponseInfo.ContentType := 'text/html';
    AResponseInfo.CharSet := 'utf-8';
    AContext.Connection.IOHandler.DefStringEncoding := IndyUTF8Encoding;
    if SameText(ARequestInfo.Command, 'GET') then begin
      //TimerMsg.Enabled := True;
      if SameText(Doc, 'GetArticles') then
        AResponseInfo.ContentText := GetArticles
      else if SameText(Doc, 'CheckStatus') then
        AResponseInfo.ContentText := CheckStatus
      else if SameText(Doc, 'GetRequestCnt') then
        AResponseInfo.ContentText := GetRequestCnt;
      try
        m.Lines.Insert(0, DateTimeToStr(Now) + ' >> [GET] [' + Doc + '] ' + ARequestInfo.UnparsedParams);
      except
      end;
    end
    else if SameText(ARequestInfo.Command, 'POST') then begin
      if Err <> '' then
        AResponseInfo.ContentText := Err
      else
        AResponseInfo.ContentText := Rcv;

      if SameText(Doc, 'sale') then
        s := SaveRcv(Rcv);

      try
        m.Lines.Insert(0, DateTimeToStr(Now) + ' >> [POST] EndPoint [' + Doc + ']' + s);
      except
      end;

      AResponseInfo.ContentText := 'Ok';
    end;

    AResponseInfo.ContentText := UTF8Encode(AResponseInfo.ContentText);
  except
    on E: Exception do
      AResponseInfo.ContentText := UTF8Encode('[srv.HTTPSrvCommandGet]' + E.Message);
  end;
  //CoUninitializeA;
  FreeAndNil(L);
end;

procedure TfMain.HTTPSrvDoneWithPostStream(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; var VCanFree: Boolean);
begin
  VCanFree := False;
end;

procedure TfMain.JSonImportTimer(Sender: TObject);
begin
  try
    JSonImport.Enabled := False;
    ProcessJSonFolder(JsonFolder);
  except
  end;
  JSonImport.Enabled := not Stoping;
end;

procedure TfMain.Log(Msg: String);
begin
  m.Lines.Add(Msg);
  WriteToLog(Msg, '');
end;

procedure TfMain.miExitClick(Sender: TObject);
begin
  Self.OnCloseQuery := nil;
  Self.Close;
end;

procedure TfMain.OnMinimize(Sender: TObject);
begin
  Hide; // This is to hide it from taskbar
  TrayIcon.Visible := True;
end;

function TfMain.GetFileList(const Dir, Mask: String; InclPath: Boolean; InclDirs: Boolean=True; RemoveExt: Boolean=False): TStringList; //VER
  function RemExt(FN: String): String;
  var P: Smallint;
  begin
    Result := FN;
    P := pos('.', FN);
    if P > 0 then
      Result := copy(FN, 1, P-1);
  end;
var
  FRec: TSearchRec;
  FDir, FName: String;
  ErrCode: Integer;
begin
  Result := TStringList.Create();
  Result.Sorted := True;
  FDir := IncludeTrailingBackslash(Dir);

  ErrCode := FindFirst(FDir+Mask, faAnyFile, FRec);
  while ErrCode = 0 do begin
    if RemoveExt then FName := RemExt(FRec.Name)
    else FName := FRec.Name;
    if (InclDirs and (FName <> '.') and (FName <> '..')) or (FRec.Attr and faDirectory = 0) then //VER
      if InclPath then Result.AddObject(FDir+FName, Pointer(FRec.Attr))
      else Result.AddObject(FName, Pointer(FRec.Attr));
    ErrCode := FindNext(FRec);
  end;
  FindClose(FRec);
end;

function TfMain.MinInteger(A, B: Integer): Integer;
begin
  Result := A;
  if Result > B then Result := B;
end;

procedure TfMain.ProcessJsonFolder(Fld: String);
var
  L, S: TStringList;
  i, k: Integer;
  Dt: TDateTime;
  FName, Step: String;
begin
  S := TStringList.Create;
  try
    Step := '--Step 1--';
    L := GetFileList(Fld, '*.json', True, False, False);
    Step := '--Step 2--';
    k := MinInteger(L.Count, 20) - 1;
    Step := '--Step 3--';
    //k := L.Count-1;
    //ProgressShow(1, L.Count, '', '', False, True, True);
    for i := 0 to k do begin
      FName := ExtractFileName(L[i]);
      if not FileExists(L[i]) then
        Continue;

      Step := '--Step 4--';
      Dt := GetFileDateTime(L[i]);
      Step := '--Step 5--';
      if Dt + (1 / 86400) * 20 > Now then
        Continue;

      S.LoadFromFile(L[i]);
      Step := '--Step 6--';
      if ProcessJsonToDB(S.Text, ExtractFileName(L[i])) then
        FileMove(L[i], JsonFolder + 'Imported\', False, True)
      else
        FileMove(L[i], JsonFolder + 'Error\', False, False);
      Step := '--Step 7--';
     //ProgressIncrease(1, '');
    end;
    //ProgressHide;
  except
    on E: Exception do begin
      Log('?? ' + DateTimeToStr(Now) + ' [ProcessJSonFolder] ' + Step + ' FileName: ' + FName + ' ' + E.Message);
    end;
  end;
  FreeAndNil(S);
  FreeAndNil(L);
end;

function TfMain.ProcessJsonToDB(JSONStr, FName: String): Boolean;
var
  i: Integer;
  JSONValue: TJSONValue;
  Sale: TSale;
  Customer: TJSONObject;
  Articles: TJSONArray;
  Article: TJSONObject;
  A: TArticle;
  sql, Er: String;
begin
  Result := False;
  try
    // Parse JSON string
    JSONValue := TJSONObject.ParseJSONValue(JSONStr);
    if JSONValue is TJSONObject then begin
      try
        Database.Execute('DELETE FROM importdt');
        Database.Execute('DELETE FROM importdata');

        Sale := TSale.Create;
        Customer := TJSONObject((JSONValue as TJSONObject).GetValue('customer'));
        try
          Sale.SaleID := (JSONValue as TJSONObject).GetValue('sale_id').Value;
          Sale.SaleNumber := (JSONValue as TJSONObject).GetValue('sale_number').Value;
          Sale.Date := ISO8601ToDate((JSONValue as TJSONObject).GetValue('date').Value);
          Sale.Customer.CustomerID := GetValue(Customer, 'customer_id');
          Sale.Customer.Name := CharsetConversion(GetValue(Customer, 'name'), UTF_8, CP1251);
          Sale.Customer.Email := GetValue(Customer, 'email');
          Sale.Customer.Address := GetValue(Customer, 'address');
          Sale.Customer.Phone := GetValue(Customer, 'phone');

          sql := 'INSERT INTO importdt(D0, D1, D2, D10, D11, D12, D13, D14)' +
            'VALUES(' + QuotedStr(Sale.SaleID) + ', ' +
               QuotedStr(Sale.SaleNumber) + ', ' +
               QuotedStr(FormatDateTime('dd.mm.yyyy', Sale.Date)) + ', ' +
               QuotedStr(Sale.Customer.CustomerID) + ', ' +
               QuotedStr(Sale.Customer.Name) + ', ' +
               QuotedStr(Sale.Customer.Email) + ', ' +
               QuotedStr(Sale.Customer.Address) + ', ' +
               QuotedStr(Sale.Customer.Phone) +') ';
          Database.Execute(sql);

          Articles := TJSONArray((JSONValue as TJSONObject).GetValue('articles'));
          for i := 0 to Articles.Count - 1 do begin
            Article := Articles.Items[i] as TJSONObject;
            A := TArticle.Create;
            A.ArticleID := Article.GetValue('article_id').Value;
            A.Price := StrToFloat(Article.GetValue('price').Value);
            A.Quantity := StrToInt(Article.GetValue('quantity').Value);
            Sale.Articles.Add(A);

            sql := 'INSERT INTO importdata(D0, D1, D2)' +
              'VALUES(' + QuotedStr(A.ArticleID) + ', ' +
                 QuotedStr(FormatFloat('0.000', A.Price)) + ', ' +
                 QuotedStr(FormatFloat('0.000', A.Quantity)) + ') ';
            Database.Execute(sql);

          end;
          Sale.TotalAmount := StrToFloat((JSONValue as TJSONObject).GetValue('total_amount').Value);
        finally
          Customer.Free;
        end;
        // Use the Sale object as needed
        m.Lines.Add('Sale ID: ' + Sale.SaleID);
        m.Lines.Add('Sale Number: ' + Sale.SaleNumber);
        m.Lines.Add('Date: ' + DateToStr(Sale.Date));
        m.Lines.Add('Customer Name: ' + Sale.Customer.Name);
        m.Lines.Add('Total Amount: ' + FloatToStr(Sale.TotalAmount));
        // Iterate through articles
        m.Lines.Add('Articles:');
        for I := 0 to Sale.Articles.Count - 1 do begin
          m.Lines.Add('  Article ID: ' + TArticle(Sale.Articles[I]).ArticleID);
          m.Lines.Add('  Price: ' + FloatToStr(TArticle(Sale.Articles[I]).Price));
          m.Lines.Add('  Quantity: ' + IntToStr(TArticle(Sale.Articles[I]).Quantity));
        end;

        // Import into Db and execute create procedure;

        sp.ExecProc;
        Er := sp.Parameters.ParamByName('Err').Value;
        if Er <> '' then
          Log('Import procedure error: ' + Er)
        else
          Result := True;
      finally
        Sale.Free;
        JSONValue := nil;
      end;
    end;
  except
    on E: Exception do
      Log(E.Message);
  end;
end;

function TfMain.SaveRcv(v: String): String;
var
  S: TStringList;
begin
  Result := JsonFolder + FormatDateTime('yymmddhhnnsszzz', Now) + '.json';
  try
    S := TStringList.Create;
    S.Text := v;
    S.SaveToFile(Result);
    Result := ' Saved to file [' + Result + ']';
  except
    on E: Exception do
      Result := E.Message;
  end;
end;

function TfMain.SetCommandText(Qry: TADOQuery; const CmdStr: String;
  SetOpen: Boolean): Integer;
begin
  Result := -1;
  try
    if Qry.Active then Qry.Close;

    Qry.SQL.Clear;
    Qry.SQL.Text := CmdStr;
    if SetOpen then begin
      Qry.Open;
      Qry.First;
    end
    else
      Qry.ExecSQL;

    Result := 0;
  except
    on E: Exception do begin
      Log('Грешка при изпълнение на SQL заявка: '#13#10 + E.Message);
    end;
  end;
end;

procedure TfMain.TrayIconDblClick(Sender: TObject);
begin
  TrayIcon.Visible := Visible;
  if Visible then  // Application is visible, so minimize it to TrayIcon
    Application.Minimize // This is to minimize the whole application
  else begin // Application is not visible, so show it
    Show; // This is to show it from taskbar
    Application.Restore; // This is to restore the whole application
    Application.BringToFront;
  end;
end;

procedure TfMain.tStartTimer(Sender: TObject);
begin
  tStart.Enabled := False;
  OnMinimize(Sender);
end;

end.
