program Boids;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMXU.Context.WebGPU,
  FBoids in 'FBoids.pas' {BoidsForm},
  UBoidsClass in 'UBoidsClass.pas';

{$R *.res}

begin
   RegisterWebGPUContext;

   Application.Initialize;
   Application.CreateForm(TBoidsForm, BoidsForm);
   Application.Run;
end.
