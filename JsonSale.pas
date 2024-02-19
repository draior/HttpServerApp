unit JsonSale;

interface

uses
  System.Classes;

type
  TCustomer = class
  private
    FCustomerID: string;
    FName: string;
    FEmail: string;
    FAddress: string;
    FPhone: string;
  public
    property CustomerID: string read FCustomerID write FCustomerID;
    property Name: string read FName write FName;
    property Email: string read FEmail write FEmail;
    property Address: string read FAddress write FAddress;
    property Phone: string read FPhone write FPhone;
  end;

  TArticle = class
  private
    FArticleID: string;
    FPrice: Double;
    FQuantity: Integer;
  public
    property ArticleID: string read FArticleID write FArticleID;
    property Price: Double read FPrice write FPrice;
    property Quantity: Integer read FQuantity write FQuantity;
  end;

  TSale = class
  private
    FSaleID: string;
    FSaleNumber: string;
    FDate: TDateTime;
    FCustomer: TCustomer;
    FArticles: TList;
    FTotalAmount: Double;
  public
    property SaleID: string read FSaleID write FSaleID;
    property SaleNumber: string read FSaleNumber write FSaleNumber;
    property Date: TDateTime read FDate write FDate;
    property Customer: TCustomer read FCustomer write FCustomer;
    property Articles: TList read FArticles write FArticles;
    property TotalAmount: Double read FTotalAmount write FTotalAmount;
    constructor Create;
    destructor Destroy; override;
  end;

implementation

{ TSale }

constructor TSale.Create;
begin
  FCustomer := TCustomer.Create;
  FArticles := TList.Create;
end;

destructor TSale.Destroy;
begin
  FCustomer.Free;
  FArticles.Free;
  inherited;
end;

end.
