program Boids;

uses
  System.StartUpCopy,
  FMX.Forms,
  FMXU.Context.WebGPU,
  FBoids in 'FBoids.pas' {BoidsForm},
  UBoidsClass in 'UBoidsClass.pas';

{$R *.res}

begin
   RegisterWebGPUContext('D:\GC\Delphi-WebGPU\dawn-x64\webgpu_dawn.dll');

   Application.Initialize;
   Application.CreateForm(TBoidsForm, BoidsForm);
   Application.Run;
end.
