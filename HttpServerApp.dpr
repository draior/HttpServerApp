program HttpServerApp;

uses
  Vcl.Forms,
  MainUnit in 'MainUnit.pas' {fMain},
  JsonSale in 'JsonSale.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfMain, fMain);
  Application.Run;
end.
