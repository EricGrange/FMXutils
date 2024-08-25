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
{    Vertex & Index buffer related utilities                           }
{                                                                      }
{**********************************************************************}
unit FMXU.VertexBuffer;

{$i fmxu.inc}

interface

uses
   System.SysUtils, System.Math.Vectors, System.RTLConsts,
   FMX.Types3D;

//: Compute barycenter of the vertex buffer
function BufferBarycenter(const buf : TVertexBuffer) : TPoint3D;
//: Compute average distance of vertex buffer points to a given point
function BufferAverageDistance(const buf : TVertexBuffer; const point : TPoint3D) : Double;

//: Offset all vertices in the buffer
procedure BufferOffset(const buf : TVertexBuffer; const offset : TPoint3D);
//: Offset all vertices then apply scale
procedure BufferOffsetAndScale(const buf : TVertexBuffer; const offset : TPoint3D; scale : Single);

//: Fill the indexbuffer with a sequence
procedure IndexBufferSetSequence(buf : TIndexBuffer; base, increment : Integer);
{: Create and fill an index buffer with quad indexes for a triangles vertex buffer
   The vertex buffer should hold a sequence of the 4 vertices of each quad }
function CreateIndexBufferQuadSequence(nbQuads : Integer) : TIndexBuffer;

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------
implementation
// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

// BufferBarycenter
//
function BufferBarycenter(const buf : TVertexBuffer) : TPoint3D;
begin
   Result := Default(TPoint3D);
   if (buf.Length = 0) or not (TVertexFormat.Vertex in buf.Format) then Exit;

   var aX : Double := 0;
   var aY := aX;
   var aZ := aX;
   var stride : UIntPtr := buf.VertexSize;
   var p := PPoint3D(buf.VerticesPtr[0]);
   for var i := 1 to buf.Length do begin
      aX := aX + p.X;
      aY := aY + p.Y;
      aZ := aZ + p.Z;
      p := Pointer(UIntPtr(p) + stride);
   end;
   Result.X := aX / buf.Length;
   Result.Y := aY / buf.Length;
   Result.Z := aZ / buf.Length;
end;

// BufferAverageDistance
//
function BufferAverageDistance(const buf : TVertexBuffer; const point : TPoint3D) : Double;
begin
   Result := 0;
   if (buf.Length = 0) or not (TVertexFormat.Vertex in buf.Format) then Exit;

   var pX := point.X;
   var pY := point.Y;
   var pZ := point.Z;
   var stride : UIntPtr := buf.VertexSize;
   var p := PPoint3D(buf.VerticesPtr[0]);
   if (pX = 0) and (pY = 0) and (pZ = 0) then begin
      for var i := 1 to buf.Length do begin
         Result := Result + Sqr(p.X) + Sqr(p.Y) + Sqr(p.Z);
         p := Pointer(UIntPtr(p) + stride);
      end;
   end else begin
      for var i := 1 to buf.Length do begin
         Result := Result + Sqr(p.X - pX) + Sqr(p.Y - py) + Sqr(p.Z - pz);
         p := Pointer(UIntPtr(p) + stride);
      end;
   end;
   Result := Sqrt(Result / buf.Length);
end;

// BufferOffset
//
procedure BufferOffset(const buf : TVertexBuffer; const offset : TPoint3D);
begin
   if (buf.Length = 0) or not (TVertexFormat.Vertex in buf.Format) then Exit;

   var dX : Single := offset.X;
   var dY : Single := offset.Y;
   var dZ : Single := offset.Z;
   var stride : UIntPtr := buf.VertexSize;
   var p := PPoint3D(buf.VerticesPtr[0]);
   for var i := 1 to buf.Length do begin
      p.X := p.X + dX;
      p.Y := p.Y + dY;
      p.Z := p.Z + dZ;
      p := Pointer(UIntPtr(p) + stride);
   end;
end;

// BufferOffsetAndScale
//
procedure BufferOffsetAndScale(const buf : TVertexBuffer; const offset : TPoint3D; scale : Single);
begin
   if (buf.Length = 0) or not (TVertexFormat.Vertex in buf.Format) then Exit;

   var dX : Single := offset.X;
   var dY : Single := offset.Y;
   var dZ : Single := offset.Z;
   var stride : UIntPtr := buf.VertexSize;
   var p := PPoint3D(buf.VerticesPtr[0]);
   for var i := 1 to buf.Length do begin
      p.X := (p.X + dX) * scale;
      p.Y := (p.Y + dY) * scale;
      p.Z := (p.Z + dZ) * scale;
      p := Pointer(UIntPtr(p) + stride);
   end;
end;

// IndexBufferSetSequence
//
procedure IndexBufferSetSequence(buf : TIndexBuffer; base, increment : Integer);
begin
   case buf.Format of
      TIndexFormat.UInt16: begin
         var v := Word(base);
         var d := Word(increment);
         var p := PWord(buf.Buffer);
         for var i := 0 to buf.Length-1 do begin
            p^ := v;
            Inc(p);
            Inc(v, d)
         end;
      end;
      TIndexFormat.UInt32: begin
         var v := UInt32(base);
         var d := UInt32(increment);
         var p := PUInt32(buf.Buffer);
         for var i := 0 to buf.Length-1 do begin
            p^ := v;
            Inc(p);
            Inc(v, d)
         end;
      end;
   else
      Assert(False);
   end;
end;

// CreateIndexBufferQuadSequence
//
function CreateIndexBufferQuadSequence(nbQuads : Integer) : TIndexBuffer;
type
   TWord6 = array [0..5] of Word;
   PWord6 = ^TWord6;
   TDWord6 = array [0..5] of UInt32;
   PDWord6 = ^TDWord6;
begin
   if nbQuads > 65536 div 4 then begin
      Result := TIndexBuffer.Create(nbQuads*6, TIndexFormat.UInt32);
      var pIndices : PDWord6 := Result.Buffer;
      var k := 0;
      for var i := 1 to nbQuads do begin
         {$IFOPT R+}{$DEFINE RANGEON}{$R-}{$ELSE}{$UNDEF RANGEON}{$ENDIF}
         pIndices[0] := k+0;
         pIndices[1] := k+1;
         pIndices[2] := k+2;
         pIndices[3] := k+0;
         pIndices[4] := k+2;
         pIndices[5] := k+3;
         {$IFDEF RANGEON}{$R+}{$UNDEF RANGEON}{$ENDIF}
         Inc(pIndices);
         Inc(k, 4);
      end;
   end else begin
      Result := TIndexBuffer.Create(nbQuads*6, TIndexFormat.UInt16);
      var pIndices : PWord6 := Result.Buffer;
      var k := 0;
      for var i := 1 to nbQuads do begin
         {$IFOPT R+}{$DEFINE RANGEON}{$R-}{$ELSE}{$UNDEF RANGEON}{$ENDIF}
         pIndices[0] := k+0;
         pIndices[1] := k+1;
         pIndices[2] := k+2;
         pIndices[3] := k+0;
         pIndices[4] := k+2;
         pIndices[5] := k+3;
         {$IFDEF RANGEON}{$R+}{$UNDEF RANGEON}{$ENDIF}
         Inc(pIndices);
         Inc(k, 4);
      end;
   end;
end;

end.
