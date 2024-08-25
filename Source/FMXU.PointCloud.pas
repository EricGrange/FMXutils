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
{    Support for Point Cloud rendering                                 }
{                                                                      }
{**********************************************************************}
unit FMXU.PointCloud;

{$i fmxu.inc}

interface

uses
   System.Classes, System.SysUtils, System.Math.Vectors, System.RTLConsts,
   FMX.Types3D, FMX.Controls3D, FMXU.Material.PointColor;

type
   {: Render a 3D point cloud  }
   TPointCloud3D = class (TControl3D)
      private
         FPoints : TVertexBuffer;
         FQuads : TVertexBuffer;
         FIndices : TIndexBuffer;
         FMaterialSource : TPointColorMaterialSource;
         FPointSize : Single;

      protected
         procedure SetPoints(const val : TVertexBuffer);
         procedure ClearQuads;

         function NeedDepthSorting : Boolean;
         procedure DepthSortPoints;

         function GetPointShape : TPointColorShape;
         procedure SetPointShape(const val : TPointColorShape);

      public
         constructor Create(AOwner: TComponent); override;
         destructor Destroy; override;

         {: Main buffer that holds Point coordinates (Vertex) and color (Color0) }
         property Points : TVertexBuffer read FPoints write SetPoints;
         {: Size of points rendering (ignored for pcsPoint) }
         property PointSize : Single read FPointSize write FPointSize;
         {: Shape of points }
         property PointShape : TPointColorShape read GetPointShape write SetPointShape default pcsQuad;

         {: Call this to take into account changes made directly to the Points buffer) }
         procedure UpdatePoints;

         procedure Render; override;

   end;

   EPointCloud3DException = class (Exception);

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------
implementation
// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

uses FMXU.VertexBuffer;

type
   TPointRecord = packed record
      V : TPoint3D;
      C : Cardinal;
   end;
   PPointRecord = ^TPointRecord;

   TPointRecord4 = packed array [0..3] of TPointRecord;
   PPointRecord4 = ^TPointRecord4;

   TPointRecordArray = packed array [0..MaxInt div 16-1] of TPointRecord;
   PPointRecordArray = ^TPointRecordArray;

// ------------------
// ------------------ TPointCloud3D ------------------
// ------------------

// Create
//
constructor TPointCloud3D.Create(AOwner: TComponent);
begin
   inherited;
   FPoints := TVertexBuffer.Create([ TVertexFormat.Vertex, TVertexFormat.Color0 ], 1);
   FPointSize := 0.05;
   FMaterialSource := TPointColorMaterialSource.Create(Self);
end;

// Destroy
//
destructor TPointCloud3D.Destroy;
begin
   inherited;
   FPoints.Free;
   ClearQuads;
end;

// ClearQuads
//
procedure TPointCloud3D.ClearQuads;
begin
   FreeAndNil(FQuads);
   FreeAndNil(FIndices);
end;

// NeedDepthSorting
//
function TPointCloud3D.NeedDepthSorting : Boolean;
begin
   Result := (PointShape in [ pcsGaussian ]) or (AbsoluteOpacity < 1);
end;

// DepthSortPoints
//
{$IFOPT R+}{$DEFINE RANGEON}{$R-}{$ELSE}{$UNDEF RANGEON}{$ENDIF}
procedure TPointCloud3D.DepthSortPoints;
type
   TDoubleArray = array [0..MaxInt div 8-1] of Double;
   PDoubleArray = ^TDoubleArray;
var
   depth : array of Double;
   vertexBuf : PPointRecordArray;

   procedure QuickSort(minIndex, maxIndex : NativeInt);
   var
     i, j, p : NativeInt;
   begin
      if maxIndex <= minIndex then Exit;
      var pDepth : PDoubleArray := Pointer(depth);
      repeat
         i := minIndex;
         j := maxIndex;
         p := (i+j) shr 1;
         repeat
            var pv := pDepth[p];
            while pDepth[i] > pv do Inc(i);
            while pDepth[j] < pv do Dec(j);
            if i <= j then begin
               var buf := pDepth[j]; pDepth[j] := pDepth[i]; pDepth[i] := buf;
               var vb := vertexBuf;
               var pRecI : PPointRecord := @vb[i];
               var pRecJ : PPointRecord := @vb[j];
               var bufRec := pRecJ^; pRecJ^ := pRecI^; pRecI^ := bufRec;
               if p = i then p := j else if p = j then p := i;
               Inc(i);
               Dec(j);
            end;
         until i > j;
         if minIndex < j then
            QuickSort(minIndex, j);
         minIndex := i;
      until i >= maxIndex;
   end;

begin
   // compute depth of all points using camera matrix Z
   var mvp := Context.CurrentModelViewProjectionMatrix;
   var mvpX := mvp.M[0].V[2];
   var mvpY := mvp.M[1].V[2];
   var mvpZ := mvp.M[2].V[2];

   SetLength(depth, Points.Length);
   var p := PPointRecord(Points.Buffer);
   for var i := 0 to Points.Length-1 do begin
      depth[i] := p.V.X * mvpX + p.V.Y * mvpY + p.V.Z * mvpZ;
      Inc(p);
   end;

   vertexBuf := Points.Buffer;
   QuickSort(0, Points.Length-1);
end;
{$IFDEF RANGEON}{$R+}{$UNDEF RANGEON}{$ENDIF}

// GetPointShape
//
function TPointCloud3D.GetPointShape : TPointColorShape;
begin
   Result := FMaterialSource.Shape;
end;

// SetPointShape
//
procedure TPointCloud3D.SetPointShape(const val : TPointColorShape);
begin
   FMaterialSource.Shape := val;
   ClearQuads;
end;

// SetPoints
//
procedure TPointCloud3D.SetPoints(const val : TVertexBuffer);
begin
   if (val = nil) or (val.Format <> [ TVertexFormat.Vertex, TVertexFormat.Color0 ]) then
      raise EPointCloud3DException.Create('Points should have vertex & color0 only');

   FPoints.Assign(val);
end;

// UpdatePoints
//
procedure TPointCloud3D.UpdatePoints;
type
   TWord6 = array [0..5] of Word;
   PWord6 = ^TWord6;
begin
   ClearQuads;

   if NeedDepthSorting then
      DepthSortPoints;

   if PointShape = pcsPoint then begin

      if Points.Length > 65536 then
         FIndices := TIndexBuffer.Create(Points.Length, TIndexFormat.UInt32)
      else FIndices := TIndexBuffer.Create(Points.Length, TIndexFormat.UInt16);
      IndexBufferSetSequence(FIndices, 0, 1);

      Exit;
   end;

   FQuads := TVertexBuffer.Create([ TVertexFormat.Vertex, TVertexFormat.Color0 ], Points.Length*4);

   var pPoints : PPointRecord := Points.Buffer;
   var pQuads : PPointRecord4 := FQuads.Buffer;
   var cDelta := $40000000;
   {$IFOPT R+}{$DEFINE RANGEON}{$R-}{$ELSE}{$UNDEF RANGEON}{$ENDIF}
   for var j := 1 to Points.Length do begin
      var c := pPoints.C and $FFFFFF;
      pQuads[0].V := pPoints.V; pQuads[0].C := c; Inc(c, cDelta);
      pQuads[1].V := pPoints.V; pQuads[1].C := c; Inc(c, cDelta);
      pQuads[2].V := pPoints.V; pQuads[2].C := c; Inc(c, cDelta);
      pQuads[3].V := pPoints.V; pQuads[3].C := c;
      Inc(pQuads);
      Inc(pPoints);
   end;
   {$IFDEF RANGEON}{$R+}{$UNDEF RANGEON}{$ENDIF}

   FIndices := CreateIndexBufferQuadSequence(Points.Length);
end;

// Render
//
procedure TPointCloud3D.Render;
begin
   if (FIndices = nil) or NeedDepthSorting then
      UpdatePoints;

   var radius := PointSize * 0.5;
   var m := Context.CurrentCameraInvMatrix.M;

   FMaterialSource.RightVector := m[1].Normalize * radius;
   FMaterialSource.UpVector := m[0].Normalize * radius;
   FMaterialSource.Shape := PointShape;

   context.PushContextStates;

   if NeedDepthSorting then begin
      Context.SetContextState(TContextState.csZWriteOff);
      Context.SetContextState(TContextState.csAlphaBlendOn)
   end else Context.SetContextState(TContextState.csAlphaBlendOff);

   var mat := FMaterialSource.Material;
   var opa := AbsoluteOpacity;
   if PointShape = pcsPoint then
      Context.DrawPoints(FPoints, FIndices, mat, opa)
   else Context.DrawTriangles(FQuads, FIndices, mat, opa);

   context.PopContextStates;
end;

end.
