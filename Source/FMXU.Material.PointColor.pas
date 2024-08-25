{**********************************************************************}
{                                                                      }
{    "The contents of this file are subject to the Mozilla Public      }
{    License Version 2.0 (the "License"); you may not use this         }
{    file except in compliance with the License. You may obtain        }
{    a copy of the License at http://www.mozilla.org/MPL/              }
{                                                                      }
{    Software distributed under the License is distributed on an       }
{    "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express       }
{    or implied. See the License for the specific language             }
{    governing rights and limitations under the License.               }
{                                                                      }
{    Material & shaders for TPointCloud3D component                    }
{                                                                      }
{**********************************************************************}
unit FMXU.Material.PointColor;

{$i fmxu.inc}

interface

uses
   System.SysUtils, System.Math.Vectors,
   FMX.Types3D, FMX.Materials, FMX.MaterialSources;

type
   (*
   Shader support class for PointCloud component,
   not meant to be used independently at the moment
   *)

   TPointColorShape = ( pcsQuad, pcsPoint, pcsDisc, pcsGaussian );

   TPointColorMaterialSource = class(TMaterialSource)
      private
         FRightVector : TVector3D;
         FUpVector : TVector3D;
         FShape : TPointColorShape;
      protected
         function CreateMaterial: TMaterial; override;
         procedure SetRightVector(const val : TVector3D);
         procedure SetUpVector(const val : TVector3D);
         procedure SetShape(const val : TPointColorShape);
      public
         property RightVector : TVector3D read FRightVector write SetRightVector;
         property UpVector : TVector3D read FUpVector write SetUpVector;
         property Shape : TPointColorShape read FShape write SetShape;

   end;

   TPointColorMaterial = class(TMaterial)
      private
         FRightVector : TVector3D;
         FUpVector : TVector3D;
         FShape : TPointColorShape;

         FVertexShader: TContextShader;
         FPixelShader: TContextShader;

      protected
         procedure PrepareShaders;
         procedure PreparePointShaders;
         procedure PrepareQuadsShaders;
         procedure PrepareUVShaders;
         procedure ClearShaders;

         procedure DoInitialize; override;
         procedure DoApply(const Context: TContext3D); override;
         class function DoGetMaterialProperty(const Prop: TMaterial.TProperty): string; override;

         property UpVector : TVector3D read FUpVector write FUpVector;
         property RightVector : TVector3D read FRightVector write FRightVector;
         property Shape : TPointColorShape read FShape write FShape;

      public
         destructor Destroy; override;
  end;

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------
implementation
// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

uses FMXU.D3DShaderCompiler, FMXU.Context, FMXU.Materials;

// ------------------
// ------------------ TPointColorMaterialSource ------------------
// ------------------

// CreateMaterial
//
function TPointColorMaterialSource.CreateMaterial: TMaterial;
begin
   var vm := TPointColorMaterial.Create;
   vm.RightVector := RightVector;
   vm.UpVector := UpVector;
   vm.Shape := FShape;
   Result := vm;
end;

// SetRightVector
//
procedure TPointColorMaterialSource.SetRightVector(const val : TVector3D);
begin
   TPointColorMaterial(Material).RightVector := val;
end;

// SetUpVector
//
procedure TPointColorMaterialSource.SetUpVector(const val : TVector3D);
begin
   TPointColorMaterial(Material).UpVector := val;
end;

// SetShape
//
procedure TPointColorMaterialSource.SetShape(const val : TPointColorShape);
begin
   if FShape <> val then begin
      FShape := val;
      var vcm := TPointColorMaterial(Material);
      if vcm <> nil then begin
         vcm.Shape := val;
         vcm.ClearShaders;
      end;
   end;
end;

// ------------------
// ------------------ TPointColorMaterial ------------------
// ------------------

// Destroy
//
destructor TPointColorMaterial.Destroy;
begin
   inherited;
   ClearShaders;
end;

// DoInitialize
//
procedure TPointColorMaterial.PrepareShaders;
begin
   inherited;

   Assert(
      ContextShaderArchitecture = TContextShaderArch.DX11,
      'Only DX11 supported right now'
   );

   case Shape of
      pcsQuad : PrepareQuadsShaders;
      pcsPoint : PreparePointShaders;
      pcsDisc, pcsGaussian : PrepareUVShaders;
   else
      Assert(False);
   end;
end;

// PreparePointShaders
//
procedure TPointColorMaterial.PreparePointShaders;
begin
   FVertexShader := CreateContextShader(TContextShaderKind.VertexShader,
      '''
      float4x4 MVPMatrix;
      void main(float4 inPos : POSITION0, float4 inColor : COLOR0,
         out float4 outPos : SV_POSITION0, out float4 outColor : COLOR0
      )
      {
         outPos = mul(MVPMatrix, inPos);
         outColor = float4(inColor.rgb, 1);
      }
      ''', [ ], [ ]
   );
   FPixelShader := CreateContextShader(TContextShaderKind.PixelShader,
      '''
      float4 main(float4 pos : SV_POSITION0, float4 color : COLOR0) : SV_Target
      {
         return color;
      }
      ''', [], []
   );
end;

// PrepareQuadsShaders
//
procedure TPointColorMaterial.PrepareQuadsShaders;
begin
   FVertexShader := CreateContextShader(TContextShaderKind.VertexShader,
      '''
      float4x4 MVPMatrix;
      float4 rightVector, upVector;
      void main(
         float4 inPos : POSITION0,         float4 inColor : COLOR0,
         out float4 outPos : SV_POSITION0, out float4 outColor : COLOR0
      )
      {
         if (inColor.a < 0.3) {
            if (inColor.a < 0.1) {
               inPos = inPos - rightVector - upVector;
            } else {
               inPos = inPos + rightVector - upVector;
            }
         } else {
            if (inColor.a < 0.6) {
               inPos = inPos + rightVector + upVector;
            } else {
               inPos = inPos - rightVector + upVector;
            }
         }
         outPos = mul(MVPMatrix, inPos);
         outColor = float4(inColor.rgb, 1);
      }
      ''', [
         'rightVector',                      'upVector'
      ], [
         TContextShaderVariableKind.Vector,  TContextShaderVariableKind.Vector
      ]
   );
   FPixelShader := CreateContextShader(TContextShaderKind.PixelShader,
      '''
      float4 main(float4 pos : SV_POSITION0, float4 color : COLOR0) : SV_Target
      {
         return color;
      }
      ''', [], []
   );
end;

// PrepareUVShaders
//
procedure TPointColorMaterial.PrepareUVShaders;
begin
   FVertexShader := CreateContextShader(TContextShaderKind.VertexShader,
      '''
      float4x4 MVPMatrix;
      float4 rightVector, upVector;
      void main(
         float4 inPos : POSITION0,
         float4 inColor : COLOR0,
         out float4 outPos : SV_POSITION0,
         out float4 outColor : COLOR0,
         out float2 uv : TEXCOORD0
      )
      {
         if (inColor.w < 0.3) {
            if (inColor.w < 0.1) {
               inPos = inPos - rightVector - upVector;
               uv = float2(-1.0, -1.0);
            } else {
               inPos = inPos + rightVector - upVector;
               uv = float2(+1.0, -1.0);
            }
         } else {
            if (inColor.w < 0.6) {
               inPos = inPos + rightVector + upVector;
               uv = float2(+1.0, +1.0);
            } else {
               inPos = inPos - rightVector + upVector;
               uv = float2(-1.0, +1.0);
            }
         }
         outPos = mul(MVPMatrix, inPos);
         outColor = float4(inColor.rgb, 1);
      }
      ''', [
         'rightVector',                      'upVector'
      ], [
         TContextShaderVariableKind.Vector,  TContextShaderVariableKind.Vector
      ]
   );
   var colorCode : AnsiString := '';
   if Shape = pcsGaussian then begin
      colorCode :=
         '''
         color.a = exp(- r2) * (1 - r2);
         color.rgb *= color.a;
         ''';
   end;
   FPixelShader := CreateContextShader(TContextShaderKind.PixelShader,
      '''
      float4 main(float4 pos : SV_POSITION0, float4 color : COLOR0, float2 uv : TEXCOORD0) : SV_Target
      {
         float r2 = dot(uv, uv);
         if (r2 >= 1.0)
            discard;
         else {
      '''
            + colorCode +
      '''
         }
         return color;
      }
      ''', [], []
   );
end;

// ClearShaders
//
procedure TPointColorMaterial.ClearShaders;
begin
   FreeAndNil(FVertexShader);
   FreeAndNil(FPixelShader);
end;

// DoInitialize
//
procedure TPointColorMaterial.DoInitialize;
begin
   // nothing
end;

// DoGetMaterialProperty
//
class function TPointColorMaterial.DoGetMaterialProperty(const Prop: TMaterial.TProperty): string;
begin
   case Prop of
      TProperty.ModelViewProjection: Result := 'MVPMatrix';
   else
      Result := '';
   end;
end;

// DoApply
//
procedure TPointColorMaterial.DoApply(const Context: TContext3D);
begin
   if FVertexShader = nil then
      PrepareShaders;

   Context.SetShaders(FVertexShader, FPixelShader);
   if Shape <> pcsPoint then begin
      Context.SetShaderVariable('rightVector', [ FRightVector ]);
      Context.SetShaderVariable('upVector', [ FUpVector ]);
   end;
end;

end.
