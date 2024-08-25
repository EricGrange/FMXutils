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
{    This unit holds context-related utilities                         }
{                                                                      }
{**********************************************************************}
unit FMXU.Context;

{$i fmxu.inc}

interface

uses System.SysUtils, FMX.Types3D;

function ContextShaderArch : TContextShaderArch;

function CreateContextShader(
   kind : TContextShaderKind; const shaderCode : AnsiString;
   const variableNames : array of String;
   const variableKinds : array of TContextShaderVariableKind
   ) : TContextShader;

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------
implementation
// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

uses FMXU.D3DShaderCompiler;

var
   vPrepared : Boolean;
   vContextShaderArch : TContextShaderArch;
   vShaderIndexBase : Integer;
   vD3D_VS_Target, vD3D_PS_Target : AnsiString;

// Prepare
//
function Prepare : TContextShaderArch;
begin
   vShaderIndexBase := 0;

   var contextClassName := TContextManager.DefaultContextClass.ClassName;
   if contextClassName = 'TDX9Context' then begin
      vContextShaderArch := TContextShaderArch.DX9;
      vD3D_VS_Target := 'vs_3_0';
      vD3D_PS_Target := 'ps_3_0';
   end else if contextClassName = 'TDX11Context' then begin
      vContextShaderArch := TContextShaderArch.DX11;
      vD3D_VS_Target := 'vs_4_0';
      vD3D_PS_Target := 'ps_4_0';
   end else if contextClassName = 'TCustomContextOpenGL' then begin
      vContextShaderArch := TContextShaderArch.GLSL;
   end else if contextClassName = 'TCustomContextMetal' then begin
      vContextShaderArch := TContextShaderArch.Metal;
      vShaderIndexBase := 1;
   end else begin
      raise EContext3DException.CreateFmt(
         'Unsupported context class "%s"', [ contextClassName ]
      );
   end;
   vPrepared := True;
   Result := vContextShaderArch;
end;

// ContextShaderArch
//
function ContextShaderArch : TContextShaderArch;
begin
   Result := vContextShaderArch;
   if Result = TContextShaderArch.Undefined then
      Result := Prepare;
end;

// ShaderVariableSize
//
function ShaderVariableSize(kind : TContextShaderVariableKind) : Integer;
begin
   if not vPrepared then Prepare;
   // will eventually be replaced by a lookup table, but unsure of all the values
   // just yet, so what's unknown is protected by asserts
   case kind of
      TContextShaderVariableKind.Matrix :
         case vContextShaderArch of
            TContextShaderArch.DX9, TContextShaderArch.GLSL, TContextShaderArch.Metal :
               Result := 4;
            TContextShaderArch.DX11 :
               Result := 64;
         else
            Result := 0;
            Assert(False, 'TODO');
         end;
      TContextShaderVariableKind.Vector :
         case vContextShaderArch of
            TContextShaderArch.DX9, TContextShaderArch.GLSL, TContextShaderArch.Metal :
               Result := 1;
            TContextShaderArch.DX11 :
               Result := 16;
         else
            Result := 0;
            Assert(False, 'TODO');
         end;
   else
      Result := 0;
      Assert(False, 'TODO');
   end;
end;

// CreateContextShader
//
function CreateContextShader(
   kind : TContextShaderKind; const shaderCode : AnsiString;
   const variableNames : array of String;
   const variableKinds : array of TContextShaderVariableKind
   ) : TContextShader;
var
   variables : array of TContextShaderVariable;
   variableIndex : Integer;
   variablePtr : ^TContextShaderVariable;

   procedure AddSource(const name : String; kind : TContextShaderVariableKind);
   begin
      var size := ShaderVariableSize(kind);
      variablePtr^ := TContextShaderVariable.Create(name, kind, variableIndex, size);
      Inc(variablePtr);
      Inc(variableIndex, size);
   end;

begin
   if not vPrepared then Prepare;

   var nbVariables := Length(variableNames);
   if Length(variableKinds) <> nbVariables then begin
      raise EContext3DException.CreateFmt(
         'CreateContextShader: mosmatched variable names & kinds arrays (%d elments vs %d)',
         [ nbVariables, Length(variableKinds) ]);
   end;

   // build variables array
   variableIndex := vShaderIndexBase;
   if kind = TContextShaderKind.VertexShader then begin
      SetLength(variables, nbVariables + 1);
      variablePtr := Pointer(variables);
      AddSource('MVPMatrix', TContextShaderVariableKind.Matrix);
   end else begin
      SetLength(variables, nbVariables);
      variablePtr := Pointer(variables);
   end;
   for var i := 0 to nbVariables-1 do
      AddSource(variableNames[i], variableKinds[i]);

   // copy or compile shader
   var shaderData : TBytes;
   case vContextShaderArch of
      TContextShaderArch.DX9, TContextShaderArch.DX11 : begin
         case kind of
            TContextShaderKind.VertexShader:
               shaderData := CompileShaderFromSource(shaderCode, 'main', vD3D_VS_Target);
            TContextShaderKind.PixelShader:
               shaderData := CompileShaderFromSource(shaderCode, 'main', vD3D_PS_Target);
         else
            Assert(False);
         end;
      end;
      TContextShaderArch.GLSL, TContextShaderArch.Metal : begin
         SetLength(shaderData, Length(shaderCode));
         System.Move(Pointer(shaderCode)^, Pointer(shaderData)^, Length(shaderCode));
      end;
   else
      Assert(False);
   end;

   var source := TContextShaderSource.Create(vContextShaderArch, shaderData, variables);

   Result := TContextShader.Create;
   Result.LoadFromData('', kind, '', source);
end;

end.

