unit FBoids;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms3D, FMX.Types3D, FMX.Forms, FMX.Graphics, 
  FMX.Dialogs, System.Math.Vectors, FMX.Controls3D, FMX.Layers3D,
  UBoidsClass, FMX.Objects3D;

type
  TBoidsForm = class(TForm3D)
    Timer1: TTimer;
    procedure Form3DRender(Sender: TObject; Context: TContext3D);
    procedure Form3DDestroy(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure Form3DCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    FBoids : TComputeBoids;
  end;

var
  BoidsForm: TBoidsForm;

implementation

{$R *.fmx}

procedure TBoidsForm.Form3DCreate(Sender: TObject);
begin
   Caption := Format('%d Boids', [ NUM_PARTICLES ]);
end;

procedure TBoidsForm.Form3DDestroy(Sender: TObject);
begin
   FBoids.Free;
end;

procedure TBoidsForm.Form3DRender(Sender: TObject; Context: TContext3D);
begin
   if FBoids = nil then
      FBoids := TComputeBoids.Create;

   FBoids.Render(Context);
end;

procedure TBoidsForm.Timer1Timer(Sender: TObject);
begin
   Invalidate;
end;

end.
