(*
   Adaptation of https://webgpu.github.io/webgpu-samples/?sample=computeBoids

   A GPU compute particle simulation that mimics the flocking behavior of birds.

   A compute shader updates two ping-pong buffers which store particle data.
   The data is used to draw instanced particles.

*)
unit UBoidsClass;

interface

uses
   System.SysUtils,
   FMX.Types3D,
   WebGPU, WebGPU.Interfaces,
   FMXU.Context.WebGPU, FMXU.WebGPU.Utils;

const
   NUM_PARTICLES = 1500;
   PARTICLES_PER_GROUP = 64;

type
   TSimParams = record
      DeltaT : Single;
      Rule1Distance : Single;
      Rule2Distance : Single;
      Rule3Distance : Single;
      Rule1Scale : Single;
      Rule2Scale : Single;
      Rule3Scale : Single;
   end;

   TComputeBoids = class
      protected
         FSimParamBuffer : IWGPUBuffer;
         FParticleBuffers : array [0..1] of IWGPUBuffer;
         FSpriteVertexBuffer : IWGPUBuffer;
         FComputePipelineLayout : IWGPUPipelineLayout;
         FRenderPipelineLayout : IWGPUPipelineLayout;
         FComputePipeline : IWGPUComputePipeline;
         FRenderPipeline : IWGPURenderPipeline;
         FParticleBindGroups : array [0..1] of IWGPUBindGroup;
         FComputeBindGroupLayout : IWGPUBindGroupLayout;
         FWorkGroupCount : UInt32;
         FSimParams : TSimParams;
         FVertexShader : IWGPUShaderModule;
         FFragmentShader : IWGPUShaderModule;
         FComputeShader : IWGPUShaderModule;
         FFrameIndex : Integer;

         procedure PrepareVertices;
         procedure SetupPipelineLayout;
         procedure PrepareUniformBuffers;
         procedure PreparePipelines;

      public
         constructor Create;
         procedure Render(aContext: TContext3D);
  end;

// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------
implementation
// ------------------------------------------------------------------
// ------------------------------------------------------------------
// ------------------------------------------------------------------

const
   cVertexShaderCode =
      '''
      struct VertexOutput {
         @builtin(position) position : vec4<f32>,
         @location(4) color : vec4<f32>,
      };

      @vertex
      fn vs_main(
         @location(0) a_particlePos : vec2<f32>,
         @location(1) a_particleVel : vec2<f32>,
         @location(2) a_pos : vec2<f32>
         ) -> VertexOutput {
            let angle = -atan2(a_particleVel.x, a_particleVel.y);
            let pos = vec2(
               (a_pos.x * cos(angle)) - (a_pos.y * sin(angle)),
               (a_pos.x * sin(angle)) + (a_pos.y * cos(angle))
            );

            var output : VertexOutput;
            output.position = vec4(pos + a_particlePos, 0.0, 1.0);
            output.color = vec4(
               1.0 - sin(angle + 1.0) - a_particleVel.y,
               pos.x * 100.0 - a_particleVel.y + 0.1,
               a_particleVel.x + cos(angle + 0.5),
               1.0
            );
            return output;
      };
      ''';
   cFragmentShaderCode =
      '''
      @fragment
      fn fs_main(@location(4) color : vec4<f32>) -> @location(0) vec4<f32> {
         return color;
      }
      ''';
   cComputeShaderCode =
      '''
      struct Particle {
         pos : vec2<f32>,
         vel : vec2<f32>,
      }
      struct SimParams {
         deltaT : f32,
         rule1Distance : f32,
         rule2Distance : f32,
         rule3Distance : f32,
         rule1Scale : f32,
         rule2Scale : f32,
         rule3Scale : f32,
      }
      struct Particles {
         particles : array<Particle>,
      }
      @binding(0) @group(0) var<uniform> params : SimParams;
      @binding(1) @group(0) var<storage, read> particlesA : Particles;
      @binding(2) @group(0) var<storage, read_write> particlesB : Particles;

      // https://github.com/austinEng/Project6-Vulkan-Flocking/blob/master/data/shaders/computeparticles/particle.comp
      @compute @workgroup_size(64)
      fn cs_main(@builtin(global_invocation_id) GlobalInvocationID : vec3<u32>) {
         var index = GlobalInvocationID.x;

         var vPos = particlesA.particles[index].pos;
         var vVel = particlesA.particles[index].vel;
         var cMass = vec2(0.0);
         var cVel = vec2(0.0);
         var colVel = vec2(0.0);
         var cMassCount = 0u;
         var cVelCount = 0u;
         var pos : vec2<f32>;
         var vel : vec2<f32>;

         for (var i = 0u; i < arrayLength(&particlesA.particles); i++) {
            if (i == index) {
               continue;
            }

            pos = particlesA.particles[i].pos.xy;
            vel = particlesA.particles[i].vel.xy;
            if (distance(pos, vPos) < params.rule1Distance) {
               cMass += pos;
               cMassCount++;
            }
            if (distance(pos, vPos) < params.rule2Distance) {
               colVel -= pos - vPos;
            }
            if (distance(pos, vPos) < params.rule3Distance) {
               cVel += vel;
               cVelCount++;
            }
         }
         if (cMassCount > 0) {
            cMass = (cMass / vec2(f32(cMassCount))) - vPos;
         }
         if (cVelCount > 0) {
            cVel /= f32(cVelCount);
         }
         vVel += (cMass * params.rule1Scale) + (colVel * params.rule2Scale) + (cVel * params.rule3Scale);

         // clamp velocity for a more pleasing simulation
         vVel = normalize(vVel) * clamp(length(vVel), 0.0, 0.1);
         // kinematic update
         vPos = vPos + (vVel * params.deltaT);
         // Wrap around boundary
         if (vPos.x < -1.0) {
            vPos.x = 1.0;
         }
         if (vPos.x > 1.0) {
            vPos.x = -1.0;
         }
         if (vPos.y < -1.0) {
            vPos.y = 1.0;
         }
         if (vPos.y > 1.0) {
            vPos.y = -1.0;
         }
         // Write back
         particlesB.particles[index].pos = vPos;
         particlesB.particles[index].vel = vVel;
      }
      ''';

// Create
//
constructor TComputeBoids.Create;
begin
   FSimParams.DeltaT := 0.04;
   FSimParams.Rule1Distance := 0.1;
   FSimParams.Rule2Distance := 0.025;
   FSimParams.Rule3Distance := 0.025;
   FSimParams.Rule1Scale := 0.02;
   FSimParams.Rule2Scale := 0.05;
   FSimParams.Rule3Scale := 0.005;

   PrepareVertices;
   SetupPipelineLayout;
   PrepareUniformBuffers;
   PreparePipelines;
end;

// PrepareVertices
//
procedure TComputeBoids.PrepareVertices;
const
   vertexBufferData: array [0..5] of Single = (
      -0.01, -0.02,
       0.01, -0.02,
       0.00,  0.02
   );
begin
   FSpriteVertexBuffer := TFMXUContext3D_WebGPU.Device.CreateBufferFromData(
      SizeOf(vertexBufferData), WGPUBufferUsage_Vertex,
      @vertexBufferData[0], 'Sprite'
   );
end;

// SetupPipelineLayout
//
procedure TComputeBoids.SetupPipelineLayout;
begin
   // Setup compute bind group layout
   var bglEntries : array [0..2] of TWGPUBindGroupLayoutEntry;
   bglEntries[0] := Default(TWGPUBindGroupLayoutEntry);
   bglEntries[0].binding := 0;
   bglEntries[0].visibility := WGPUShaderStage_Compute;
   bglEntries[0].buffer.&type := WGPUBufferBindingType_Uniform;
   bglEntries[0].buffer.minBindingSize := SizeOf(TSimParams);

   bglEntries[1] := Default(TWGPUBindGroupLayoutEntry);
   bglEntries[1].binding := 1;
   bglEntries[1].visibility := WGPUShaderStage_Compute;
   bglEntries[1].buffer.&type := WGPUBufferBindingType_ReadOnlyStorage;
   bglEntries[1].buffer.minBindingSize := NUM_PARTICLES * 16;

   bglEntries[2] := Default(TWGPUBindGroupLayoutEntry);
   bglEntries[2].binding := 2;
   bglEntries[2].visibility := WGPUShaderStage_Compute;
   bglEntries[2].buffer.&type := WGPUBufferBindingType_Storage;
   bglEntries[2].buffer.minBindingSize := NUM_PARTICLES * 16;

   var bglDesc := Default(TWGPUBindGroupLayoutDescriptor);
   bglDesc.&label := 'Compute bind group layout';
   bglDesc.entryCount := Length(bglEntries);
   bglDesc.entries := @bglEntries[0];

   var device := TFMXUContext3D_WebGPU.Device.Device;

   FComputeBindGroupLayout := device.CreateBindGroupLayout(bglDesc);
   Assert(FComputeBindGroupLayout <> nil, 'Failed to create compute bind group layout');

   // Setup compute pipeline layout
   var computePipelineLayoutDesc := Default(TWGPUPipelineLayoutDescriptor);
   var bindGroupLayoutHandle := FComputeBindGroupLayout.GetHandle;
   computePipelineLayoutDesc.&label := 'Compute pipeline layout';
   computePipelineLayoutDesc.bindGroupLayoutCount := 1;
   computePipelineLayoutDesc.bindGroupLayouts := @bindGroupLayoutHandle;

   FComputePipelineLayout := device.CreatePipelineLayout(computePipelineLayoutDesc);
   Assert(FComputePipelineLayout <> nil, 'Failed to create compute pipeline layout');

   // Setup render pipeline layout (with empty bind group layout)
   var renderPipelineLayoutDesc := Default(TWGPUPipelineLayoutDescriptor);
   renderPipelineLayoutDesc.&label := 'Render pipeline layout';
   renderPipelineLayoutDesc.bindGroupLayoutCount := 0;
   renderPipelineLayoutDesc.bindGroupLayouts := nil;

   FRenderPipelineLayout := device.CreatePipelineLayout(renderPipelineLayoutDesc);
   Assert(FRenderPipelineLayout <> nil, 'Failed to create render pipeline layout');
end;

// PrepareUniformBuffers
//
procedure TComputeBoids.PrepareUniformBuffers;
var
   particleData : array of Single;
begin
   // Create simulation parameters buffer
   FSimParamBuffer := TFMXUContext3D_WebGPU.Device.CreateBufferFromData(
      SizeOf(FSimParams), WGPUBufferUsage_Uniform,
      @FSimParams, 'SimParams'
   );
   Assert(FSimParamBuffer <> nil, 'Failed to create simulation parameters buffer');

   // Create particle data buffers
   SetLength(particleData, NUM_PARTICLES * 4);
   for var i := 0 to NUM_PARTICLES - 1 do begin
      particleData[i * 4 + 0] := 2 * (Random - 0.5);        // posx
      particleData[i * 4 + 1] := 2 * (Random - 0.5);        // posy
      particleData[i * 4 + 2] := 2 * (Random - 0.5) * 0.1;  // velx
      particleData[i * 4 + 3] := 2 * (Random - 0.5) * 0.1;  // vely
   end;

   var particlesDataSize := SizeOf(Single) * Length(particleData);

   for var i := 0 to 1 do begin
      FParticleBuffers[i] := TFMXUContext3D_WebGPU.Device.CreateBufferFromData(
         particlesDataSize, WGPUBufferUsage_Vertex or WGPUBufferUsage_Storage,
         @particleData[0], UTF8Encode('Particles' + Char(Ord('0') + i))
      );
      Assert(FParticleBuffers[i] <> nil, Format('Failed to create particle buffer %d', [i]));
   end;

   // Create two bind groups, one for each buffer as the src where the alternate buffer is used as the dst
   for var i := 0 to 1 do begin
      var bgEntries : array [0..2] of TWGPUBindGroupEntry;
      bgEntries[0] := Default(TWGPUBindGroupEntry);
      bgEntries[0].binding := 0;
      bgEntries[0].buffer := FSimParamBuffer.GetHandle;
      bgEntries[0].offset := 0;
      bgEntries[0].size := SizeOf(FSimParams);

      bgEntries[1] := Default(TWGPUBindGroupEntry);
      bgEntries[1].binding := 1;
      bgEntries[1].buffer := FParticleBuffers[i].GetHandle;
      bgEntries[1].offset := 0;
      bgEntries[1].size := particlesDataSize;

      bgEntries[2] := Default(TWGPUBindGroupEntry);
      bgEntries[2].binding := 2;
      bgEntries[2].buffer := FParticleBuffers[(i + 1) mod 2].GetHandle;  // bind to opposite buffer
      bgEntries[2].offset := 0;
      bgEntries[2].size := particlesDataSize;

      var bgDesc := Default(TWGPUBindGroupDescriptor);
      bgDesc.&label := PAnsiChar(AnsiString(Format('Particle compute bind group %d', [i])));
      bgDesc.layout := FComputeBindGroupLayout.GetHandle;
      bgDesc.entryCount := Length(bgEntries);
      bgDesc.entries := @bgEntries[0];

      FParticleBindGroups[i] := TFMXUContext3D_WebGPU.Device.Device.CreateBindGroup(bgDesc);
      Assert(FParticleBindGroups[i] <> nil, Format('Failed to create particle bind group %d', [i]));
   end;

   // Calculate work group count
   FWorkGroupCount := NUM_PARTICLES div PARTICLES_PER_GROUP;
   if (NUM_PARTICLES mod PARTICLES_PER_GROUP) > 0 then
      Inc(FWorkGroupCount);
end;

// PreparePipelines
//
procedure TComputeBoids.PreparePipelines;
begin
   // Primitive state
   var primitiveState := Default(TWGPUPrimitiveState);
   primitiveState.topology := WGPUPrimitiveTopology_TriangleList;
   primitiveState.frontFace := WGPUFrontFace_CCW;
   primitiveState.cullMode := WGPUCullMode_None;

   // Color target state
   var blendState := Default(TWGPUBlendState);
   blendState.color.operation := WGPUBlendOperation_Add;
   blendState.color.srcFactor := WGPUBlendFactor_SrcAlpha;
   blendState.color.dstFactor := WGPUBlendFactor_OneMinusSrcAlpha;
   blendState.alpha.operation := WGPUBlendOperation_Add;
   blendState.alpha.srcFactor := WGPUBlendFactor_One;
   blendState.alpha.dstFactor := WGPUBlendFactor_OneMinusSrcAlpha;

   var colorTargetState := Default(TWGPUColorTargetState);
   colorTargetState.format := WGPUTextureFormat_BGRA8Unorm;
   colorTargetState.blend := @blendState;
   colorTargetState.writeMask := WGPUColorWriteMask_All;

   // Depth stencil state
   // Original Boids sample doesn't have a depth/stencil, as it's not needed
   // but FMX has one, so we need it to have compatible pipeline
   var depthStencilState := Default(TWGPUDepthStencilState);
   depthStencilState.format := WGPUTextureFormat_Depth24Plus;
   depthStencilState.depthWriteEnabled := WGPUOptionalBool_True;
   depthStencilState.depthCompare := WGPUCompareFunction_Less;
   depthStencilState.stencilFront.compare := WGPUCompareFunction_Always;
   depthStencilState.stencilFront.failOp := WGPUStencilOperation_Keep;
   depthStencilState.stencilFront.depthFailOp := WGPUStencilOperation_Keep;
   depthStencilState.stencilFront.passOp := WGPUStencilOperation_Keep;
   depthStencilState.stencilBack := depthStencilState.stencilFront;
   depthStencilState.stencilReadMask := UInt32(-1);
   depthStencilState.stencilWriteMask := UInt32(-1);

   // Vertex state
   var vertexAttributes : array[0..2] of TWGPUVertexAttribute;
   vertexAttributes[0].shaderLocation := 0;
   vertexAttributes[0].offset := 0;
   vertexAttributes[0].format := WGPUVertexFormat_Float32x2;

   vertexAttributes[1].shaderLocation := 1;
   vertexAttributes[1].offset := 2 * SizeOf(Single);
   vertexAttributes[1].format := WGPUVertexFormat_Float32x2;

   vertexAttributes[2].shaderLocation := 2;
   vertexAttributes[2].offset := 0;
   vertexAttributes[2].format := WGPUVertexFormat_Float32x2;

   var vertexBufferLayouts : array[0..1] of TWGPUVertexBufferLayout;
   vertexBufferLayouts[0].arrayStride := 4 * SizeOf(Single);
   vertexBufferLayouts[0].stepMode := WGPUVertexStepMode_Instance;
   vertexBufferLayouts[0].attributeCount := 2;
   vertexBufferLayouts[0].attributes := @vertexAttributes[0];

   vertexBufferLayouts[1].arrayStride := 2 * SizeOf(Single);
   vertexBufferLayouts[1].stepMode := WGPUVertexStepMode_Vertex;
   vertexBufferLayouts[1].attributeCount := 1;
   vertexBufferLayouts[1].attributes := @vertexAttributes[2];

   var vertexState := Default(TWGPUVertexState);
   FVertexShader := TFMXUContext3D_WebGPU.Device.CompileShaderModule(cVertexShaderCode);
   vertexState.module := FVertexShader.GetHandle;
   vertexState.entryPoint := 'vs_main';
   vertexState.bufferCount := Length(vertexBufferLayouts);
   vertexState.buffers := @vertexBufferLayouts[0];

   // Fragment state
   var fragmentState := Default(TWGPUFragmentState);
   FFragmentShader := TFMXUContext3D_WebGPU.Device.CompileShaderModule(cFragmentShaderCode);
   fragmentState.module := FFragmentShader.GetHandle;
   fragmentState.entryPoint := 'fs_main';
   fragmentState.targetCount := 1;
   fragmentState.targets := @colorTargetState;

   // Multisample state
   var multisampleState := Default(TWGPUMultisampleState);
   multisampleState.count := 1;
   multisampleState.mask := $FFFFFFFF;

   // Create compute pipeline
   var computePipelineDescriptor := Default(TWGPUComputePipelineDescriptor);
   computePipelineDescriptor.&label := 'Compute boids pipeline';
   computePipelineDescriptor.layout := FComputePipelineLayout.GetHandle;
   FComputeShader := TFMXUContext3D_WebGPU.Device.CompileShaderModule(cComputeShaderCode);
   computePipelineDescriptor.compute.module := FComputeShader.GetHandle;
   computePipelineDescriptor.compute.entryPoint := 'cs_main';

   FComputePipeline := TFMXUContext3D_WebGPU.Device.Device.CreateComputePipeline(computePipelineDescriptor);
   Assert(FComputePipeline <> nil, 'Failed to create compute pipeline');

   // Create render pipeline
   var renderPipelineDescriptor := Default(TWGPURenderPipelineDescriptor);
   renderPipelineDescriptor.&label := 'Boids render pipeline';
   renderPipelineDescriptor.layout := FRenderPipelineLayout.GetHandle;
   renderPipelineDescriptor.vertex := vertexState;
   renderPipelineDescriptor.primitive := primitiveState;
   renderPipelineDescriptor.fragment := @fragmentState;
   renderPipelineDescriptor.multisample := multisampleState;
   renderPipelineDescriptor.depthStencil := @depthStencilState;

   FRenderPipeline := TFMXUContext3D_WebGPU.Device.Device.CreateRenderPipeline(renderPipelineDescriptor);
   Assert(FRenderPipeline <> nil, 'Failed to create render pipeline');
end;

procedure TComputeBoids.Render(aContext: TContext3D);
begin
   var context := aContext as TFMXUContext3D_WebGPU;

   // We have to stop the current FMX render pass to start our compute pass
   context.EndRenderPassEncoder;

   var commandEncoder := context.CommandEncoder;

   // Compute pass
   var computePassEncoder := commandEncoder.BeginComputePass;
   computePassEncoder.SetPipeline(FComputePipeline);
   computePassEncoder.SetBindGroup(0, FParticleBindGroups[FFrameIndex mod 2], 0, nil);
   computePassEncoder.DispatchWorkgroups(FWorkGroupCount, 1, 1);
   computePassEncoder.&End;

   // Begin a new render pass, but don't clear anything!
   context.BeginRenderPassEncoder([], 0, 0, 0);

   var renderPassEncoder := context.RenderPassEncoder;

   renderPassEncoder.SetPipeline(FRenderPipeline);
   renderPassEncoder.SetVertexBuffer(0, FParticleBuffers[(FFrameIndex + 1) mod 2], 0, WGPU_WHOLE_SIZE);
   renderPassEncoder.SetVertexBuffer(1, FSpriteVertexBuffer, 0, WGPU_WHOLE_SIZE);
   renderPassEncoder.Draw(3, NUM_PARTICLES, 0, 0);

   Inc(FFrameIndex);
end;

end.
