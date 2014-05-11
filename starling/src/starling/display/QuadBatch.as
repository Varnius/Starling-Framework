// =================================================================================================
//
//	Starling Framework
//	Copyright 2012 Gamua OG. All Rights Reserved.
//
//	This program is free software. You can redistribute and/or modify it
//	in accordance with the terms of the accompanying license agreement.
//
// =================================================================================================

package starling.display
{
    import flash.display3D.Context3D;
    import flash.display3D.Context3DProgramType;
    import flash.display3D.Context3DTextureFormat;
    import flash.display3D.Context3DVertexBufferFormat;
    import flash.display3D.IndexBuffer3D;
    import flash.display3D.Program3D;
    import flash.display3D.VertexBuffer3D;
    import flash.geom.Matrix;
    import flash.geom.Matrix3D;
    import flash.geom.Rectangle;
    import flash.utils.Dictionary;
    import flash.utils.getQualifiedClassName;
    
    import starling.core.RenderSupport;
    import starling.core.Starling;
    import starling.core.starling_internal;
    import starling.errors.MissingContextError;
    import starling.events.Event;
    import starling.extensions.defferedShading.MaterialProperties;
    import starling.extensions.defferedShading.RenderPass;
    import starling.extensions.defferedShading.Utils;
    import starling.filters.FragmentFilter;
    import starling.filters.FragmentFilterMode;
    import starling.textures.Texture;
    import starling.textures.TextureSmoothing;
    import starling.utils.MatrixUtil;
    import starling.utils.VertexData;
    
    use namespace starling_internal;
    
    /** Optimizes rendering of a number of quads with an identical state.
     * 
     *  <p>The majority of all rendered objects in Starling are quads. In fact, all the default
     *  leaf nodes of Starling are quads (the Image and Quad classes). The rendering of those 
     *  quads can be accelerated by a big factor if all quads with an identical state are sent 
     *  to the GPU in just one call. That's what the QuadBatch class can do.</p>
     *  
     *  <p>The 'flatten' method of the Sprite class uses this class internally to optimize its 
     *  rendering performance. In most situations, it is recommended to stick with flattened
     *  sprites, because they are easier to use. Sometimes, however, it makes sense
     *  to use the QuadBatch class directly: e.g. you can add one quad multiple times to 
     *  a quad batch, whereas you can only add it once to a sprite. Furthermore, this class
     *  does not dispatch <code>ADDED</code> or <code>ADDED_TO_STAGE</code> events when a quad
     *  is added, which makes it more lightweight.</p>
     *  
     *  <p>One QuadBatch object is bound to a specific render state. The first object you add to a 
     *  batch will decide on the QuadBatch's state, that is: its texture, its settings for 
     *  smoothing and blending, and if it's tinted (colored vertices and/or transparency). 
     *  When you reset the batch, it will accept a new state on the next added quad.</p> 
     *  
     *  <p>The class extends DisplayObject, but you can use it even without adding it to the
     *  display tree. Just call the 'renderCustom' method from within another render method,
     *  and pass appropriate values for transformation matrix, alpha and blend mode.</p>
     *
     *  @see Sprite  
     */ 
    public class QuadBatch extends DisplayObject
    {
        /** The maximum number of quads that can be displayed by one QuadBatch. */
		public static const MAX_NUM_QUADS:int = 16383;
        
        private static const QUAD_PROGRAM_NAME:String = "QB_q";
		private static const QUAD_PROGRAM_NAME_DEFERRED:String = "QB_q_def";
        
        private var mNumQuads:int;
        private var mSyncRequired:Boolean;
        private var mBatchable:Boolean;

        private var mTinted:Boolean;
        private var mTexture:Texture;
        private var mSmoothing:String;
        
        private var mVertexBuffer:VertexBuffer3D;
        private var mIndexData:Vector.<uint>;
        private var mIndexBuffer:IndexBuffer3D;
        
        /** The raw vertex data of the quad. After modifying its contents, call
         *  'onVertexDataChanged' to upload the changes to the vertex buffers. Don't change the
         *  size of this object manually; instead, use the 'capacity' property of the QuadBatch. */
        protected var mVertexData:VertexData;

        /** Helper objects. */
        private static var sHelperMatrix:Matrix = new Matrix();
        private static var sRenderAlpha:Vector.<Number> = new <Number>[1.0, 1.0, 1.0, 1.0];
        private static var sRenderMatrix:Matrix3D = new Matrix3D();
        private static var sProgramNameCache:Dictionary = new Dictionary();
		
		// Deferred shading
		
		private var deferredQuadNormal:Vector.<Number> = new <Number>[0.5, 0.5, 1.0, 1.0];		
		private var deferredQuadSpecularParams:Vector.<Number> = new <Number>[MaterialProperties.DEFAULT_SPECULAR_POWER, MaterialProperties.DEFAULT_SPECULAR_INTENSITY, 1.0, 0.0];
		private var specularParams:Vector.<Number> = new <Number>[0.0, 0.0, 0.0, 0.0];
        
        /** Creates a new QuadBatch instance with empty batch data. */
        public function QuadBatch()
        {
            mVertexData = new VertexData(0, true);
            mIndexData = new <uint>[];
            mNumQuads = 0;
            mTinted = false;
            mSyncRequired = false;
            mBatchable = false;
            
            // Handle lost context. We use the conventional event here (not the one from Starling)
            // so we're able to create a weak event listener; this avoids memory leaks when people 
            // forget to call "dispose" on the QuadBatch.
            Starling.current.stage3D.addEventListener(Event.CONTEXT3D_CREATE, 
                                                      onContextCreated, false, 0, true);
        }
        
        /** Disposes vertex- and index-buffer. */
        public override function dispose():void
        {
            Starling.current.stage3D.removeEventListener(Event.CONTEXT3D_CREATE, onContextCreated);
			destroyBuffers();
			
            mVertexData.numVertices = 0;
            mIndexData.length = 0;
            mNumQuads = 0;

            super.dispose();
        }
        
        private function onContextCreated(event:Object):void
        {
            createBuffers();
        }
        
        /** Call this method after manually changing the contents of 'mVertexData'. */
        protected function onVertexDataChanged():void
        {
            mSyncRequired = true;
        }
        
        /** Creates a duplicate of the QuadBatch object. */
        public function clone():QuadBatch
        {
            var clone:QuadBatch = new QuadBatch();
            clone.mVertexData = mVertexData.clone(0, mNumQuads * 4);
            clone.mIndexData = mIndexData.slice(0, mNumQuads * 6);
            clone.mNumQuads = mNumQuads;
            clone.mTinted = mTinted;
            clone.mTexture = mTexture;
            clone.mSmoothing = mSmoothing;
            clone.mSyncRequired = true;
            clone.blendMode = blendMode;
            clone.alpha = alpha;
            return clone;
        }
        
        private function expand():void
        {
            var oldCapacity:int = this.capacity;
            this.capacity = oldCapacity < 8 ? 16 : oldCapacity * 2;
        }
        
        private function createBuffers():void
        {
			destroyBuffers();
			
            var numVertices:int = mVertexData.numVertices;
            var numIndices:int = mIndexData.length;
            var context:Context3D = Starling.context;

            if (numVertices == 0) return;
            if (context == null)  throw new MissingContextError();
            
            mVertexBuffer = context.createVertexBuffer(numVertices, VertexData.ELEMENTS_PER_VERTEX);
            mVertexBuffer.uploadFromVector(mVertexData.rawData, 0, numVertices);
            
            mIndexBuffer = context.createIndexBuffer(numIndices);
            mIndexBuffer.uploadFromVector(mIndexData, 0, numIndices);
            
            mSyncRequired = false;
        }
		
		private function destroyBuffers():void
		{
			if (mVertexBuffer)
			{
				mVertexBuffer.dispose();
				mVertexBuffer = null;
			}
			
			if (mIndexBuffer)
			{
				mIndexBuffer.dispose();
				mIndexBuffer = null;
			}
		}
        
        /** Uploads the raw data of all batched quads to the vertex buffer; furthermore,
         *  registers the required programs if they haven't been registered yet. */
        private function syncBuffers():void
        {
            if (mVertexBuffer == null)
            {
                createBuffers();
            }
            else
            {
                // as last parameter, we could also use 'mNumQuads * 4', but on some GPU hardware (iOS!),
                // this is slower than updating the complete buffer.
                mVertexBuffer.uploadFromVector(mVertexData.rawData, 0, mVertexData.numVertices);
                mSyncRequired = false;
            }
        }
		
        /** Renders the current batch with custom settings for model-view-projection matrix, alpha 
         *  and blend mode. This makes it possible to render batches that are not part of the 
         *  display list. */ 
        public function renderCustom(mvpMatrix:Matrix, parentAlpha:Number=1.0,
                                     blendMode:String=null):void
        {
            if (mNumQuads == 0) return;
            if (mSyncRequired) syncBuffers();
            
			var currPass:String = Starling.current.renderSupport.renderPass;
			var MRTPass:Boolean = currPass == RenderPass.MRT;
            var pma:Boolean = mVertexData.premultipliedAlpha;
            var context:Context3D = Starling.context;
            var tinted:Boolean = mTinted || (parentAlpha != 1.0);
            /*var programName:String = mTexture ? 
                getImageProgramName(tinted, mTexture.mipMapping, mTexture.repeat, mTexture.format, mSmoothing, currPass) : 
                (MRTPass ? QUAD_PROGRAM_NAME_DEFERRED : QUAD_PROGRAM_NAME);*/
            
            sRenderAlpha[0] = sRenderAlpha[1] = sRenderAlpha[2] = pma ? parentAlpha : 1.0;
            sRenderAlpha[3] = parentAlpha;
            
            MatrixUtil.convertTo3D(mvpMatrix, sRenderMatrix);
            RenderSupport.setBlendFactors(pma, blendMode ? blendMode : this.blendMode);
            
            context.setProgram(getProgram(tinted, currPass));
            context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, sRenderAlpha, 1);
            context.setProgramConstantsFromMatrix(Context3DProgramType.VERTEX, 1, sRenderMatrix, true);
			
			// Set program constants for deferred pass
			
            context.setVertexBufferAt(0, mVertexBuffer, VertexData.POSITION_OFFSET, 
                                      Context3DVertexBufferFormat.FLOAT_2); 
            
            if (mTexture == null || tinted)
                context.setVertexBufferAt(1, mVertexBuffer, VertexData.COLOR_OFFSET, 
                                          Context3DVertexBufferFormat.FLOAT_4);
			
			// Image
			
            if (mTexture)
            {
                context.setTextureAt(0, mTexture.base);
                context.setVertexBufferAt(2, mVertexBuffer, VertexData.TEXCOORD_OFFSET, 
                                          Context3DVertexBufferFormat.FLOAT_2);
				
				// Set textures for deferred pass	
				
				if (MRTPass)
				{		
					var specPower:Number;
					var specIntensity:Number;					
					var normalMapPresent:Boolean;
					var depthMapPresent:Boolean;
					var propsPresent:Boolean = mTexture.materialProperties;
					
					if(propsPresent)
					{
						normalMapPresent = mTexture.materialProperties.normalMap;
						depthMapPresent = mTexture.materialProperties.depthMap;
					}
					else
					{
						normalMapPresent = false;
						depthMapPresent = false;
					}				
					
					// Set specular params constants, fc5
					// Also, scale to fit into range of [0.0, 1.0] as all output is clipped when non-float RT is used
					
					if(propsPresent)
					{
						specularParams[0] = mTexture.materialProperties.specularPower / MaterialProperties.SPECULAR_POWER_SCALE;						
						specularParams[1] = mTexture.materialProperties.specularIntensity / MaterialProperties.SPECULAR_INTENSITY_SCALE;
					}
					else
					{
						specularParams[0] = 0;						
						specularParams[1] = 0; 
					}
					
					context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 5, specularParams, 1);
					
					// Set samplers	
					
					context.setTextureAt(1, normalMapPresent ? mTexture.materialProperties.normalMap.base : Starling.current.defaultNormalMap.base);	
					context.setTextureAt(2, depthMapPresent ? mTexture.materialProperties.depthMap.base : Starling.current.defaultDepthMap.base);
				}		
            }
			
			// Quad
			
			else
			{
				if (MRTPass)
				{			
					// Set default normal color for quads				
					context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 5, deferredQuadNormal, 1);					
					context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 6, deferredQuadSpecularParams, 1);
				}				 
			}
            
            context.drawTriangles(mIndexBuffer, 0, mNumQuads * 2);
            
            if (mTexture)
            {
                context.setTextureAt(0, null);
                context.setVertexBufferAt(2, null);
				
				if (MRTPass)
				{
					// Unset textures		
					context.setTextureAt(1, null);
					context.setTextureAt(2, null);
				}
            }
            
            context.setVertexBufferAt(1, null);
            context.setVertexBufferAt(0, null);
        }
        
        /** Resets the batch. The vertex- and index-buffers remain their size, so that they
         *  can be reused quickly. */  
        public function reset():void
        {
            mNumQuads = 0;
            mTexture = null;
            mSmoothing = null;
            mSyncRequired = true;
        }
        
        /** Adds an image to the batch. This method internally calls 'addQuad' with the correct
         *  parameters for 'texture' and 'smoothing'. */ 
        public function addImage(image:Image, parentAlpha:Number=1.0, modelViewMatrix:Matrix=null,
                                 blendMode:String=null):void
        {
            addQuad(image, parentAlpha, image.texture, image.smoothing, modelViewMatrix, blendMode);
        }
        
        /** Adds a quad to the batch. The first quad determines the state of the batch,
         *  i.e. the values for texture, smoothing and blendmode. When you add additional quads,  
         *  make sure they share that state (e.g. with the 'isStateChange' method), or reset
         *  the batch. */ 
        public function addQuad(quad:Quad, parentAlpha:Number=1.0, texture:Texture=null, 
                                smoothing:String=null, modelViewMatrix:Matrix=null, 
                                blendMode:String=null):void
        {
            if (modelViewMatrix == null)
                modelViewMatrix = quad.transformationMatrix;
            
            var alpha:Number = parentAlpha * quad.alpha;
            var vertexID:int = mNumQuads * 4;
            
            if (mNumQuads + 1 > mVertexData.numVertices / 4) expand();
            if (mNumQuads == 0) 
            {
                this.blendMode = blendMode ? blendMode : quad.blendMode;
                mTexture = texture;
                mTinted = texture ? (quad.tinted || parentAlpha != 1.0) : false;
                mSmoothing = smoothing;
                mVertexData.setPremultipliedAlpha(quad.premultipliedAlpha);
            }
            
            quad.copyVertexDataTransformedTo(mVertexData, vertexID, modelViewMatrix);
            
            if (alpha != 1.0)
                mVertexData.scaleAlpha(vertexID, alpha, 4);

            mSyncRequired = true;
            mNumQuads++;
        }
        
        /** Adds another QuadBatch to this batch. Just like the 'addQuad' method, you have to
         *  make sure that you only add batches with an equal state. */
        public function addQuadBatch(quadBatch:QuadBatch, parentAlpha:Number=1.0, 
                                     modelViewMatrix:Matrix=null, blendMode:String=null):void
        {
            if (modelViewMatrix == null)
                modelViewMatrix = quadBatch.transformationMatrix;
            
            var tinted:Boolean = quadBatch.mTinted || parentAlpha != 1.0;
            var alpha:Number = parentAlpha * quadBatch.alpha;
            var vertexID:int = mNumQuads * 4;
            var numQuads:int = quadBatch.numQuads;
            
            if (mNumQuads + numQuads > capacity) capacity = mNumQuads + numQuads;
            if (mNumQuads == 0) 
            {
                this.blendMode = blendMode ? blendMode : quadBatch.blendMode;
                mTexture = quadBatch.mTexture;
                mTinted = tinted;
                mSmoothing = quadBatch.mSmoothing;
                mVertexData.setPremultipliedAlpha(quadBatch.mVertexData.premultipliedAlpha, false);
            }
            
            quadBatch.mVertexData.copyTransformedTo(mVertexData, vertexID, modelViewMatrix,
                                                    0, numQuads*4);
            
            if (alpha != 1.0)
                mVertexData.scaleAlpha(vertexID, alpha, numQuads*4);
            
            mSyncRequired = true;
            mNumQuads += numQuads;
        }
        
        /** Indicates if specific quads can be added to the batch without causing a state change. 
         *  A state change occurs if the quad uses a different base texture, has a different 
         *  'tinted', 'smoothing', 'repeat' or 'blendMode' setting, or if the batch is full
         *  (one batch can contain up to 8192 quads). */
        public function isStateChange(tinted:Boolean, parentAlpha:Number, texture:Texture, 
                                      smoothing:String, blendMode:String, numQuads:int=1):Boolean
        {
            if (mNumQuads == 0) return false;
            else if (mNumQuads + numQuads > MAX_NUM_QUADS) return true; // maximum buffer size
            else if (mTexture == null && texture == null) 
                return this.blendMode != blendMode;
            else if (mTexture != null && texture != null)
                return mTexture.base != texture.base ||
                       mTexture.repeat != texture.repeat ||
                       mSmoothing != smoothing ||
                       mTinted != (tinted || parentAlpha != 1.0) ||
                       this.blendMode != blendMode;
            else return true;
        }
        
        // utility methods for manual vertex-modification
        
        /** Transforms the vertices of a certain quad by the given matrix. */
        public function transformQuad(quadID:int, matrix:Matrix):void
        {
            mVertexData.transformVertex(quadID * 4, matrix, 4);
            mSyncRequired = true;
        }
        
        /** Returns the color of one vertex of a specific quad. */
        public function getVertexColor(quadID:int, vertexID:int):uint
        {
            return mVertexData.getColor(quadID * 4 + vertexID);
        }
        
        /** Updates the color of one vertex of a specific quad. */
        public function setVertexColor(quadID:int, vertexID:int, color:uint):void
        {
            mVertexData.setColor(quadID * 4 + vertexID, color);
            mSyncRequired = true;
        }
        
        /** Returns the alpha value of one vertex of a specific quad. */
        public function getVertexAlpha(quadID:int, vertexID:int):Number
        {
            return mVertexData.getAlpha(quadID * 4 + vertexID);
        }
        
        /** Updates the alpha value of one vertex of a specific quad. */
        public function setVertexAlpha(quadID:int, vertexID:int, alpha:Number):void
        {
            mVertexData.setAlpha(quadID * 4 + vertexID, alpha);
            mSyncRequired = true;
        }
        
        /** Returns the color of the first vertex of a specific quad. */
        public function getQuadColor(quadID:int):uint
        {
            return mVertexData.getColor(quadID * 4);
        }
        
        /** Updates the color of a specific quad. */
        public function setQuadColor(quadID:int, color:uint):void
        {
            for (var i:int=0; i<4; ++i)
                mVertexData.setColor(quadID * 4 + i, color);
            
            mSyncRequired = true;
        }
        
        /** Returns the alpha value of the first vertex of a specific quad. */
        public function getQuadAlpha(quadID:int):Number
        {
            return mVertexData.getAlpha(quadID * 4);
        }
        
        /** Updates the alpha value of a specific quad. */
        public function setQuadAlpha(quadID:int, alpha:Number):void
        {
            for (var i:int=0; i<4; ++i)
                mVertexData.setAlpha(quadID * 4 + i, alpha);
            
            mSyncRequired = true;
        }
        
        /** Calculates the bounds of a specific quad, optionally transformed by a matrix.
         *  If you pass a 'resultRect', the result will be stored in this rectangle
         *  instead of creating a new object. */
        public function getQuadBounds(quadID:int, transformationMatrix:Matrix=null,
                                      resultRect:Rectangle=null):Rectangle
        {
            return mVertexData.getBounds(transformationMatrix, quadID * 4, 4, resultRect);
        }
        
        // display object methods
        
        /** @inheritDoc */
        public override function getBounds(targetSpace:DisplayObject, resultRect:Rectangle=null):Rectangle
        {
            if (resultRect == null) resultRect = new Rectangle();
            
            var transformationMatrix:Matrix = targetSpace == this ?
                null : getTransformationMatrix(targetSpace, sHelperMatrix);
            
            return mVertexData.getBounds(transformationMatrix, 0, mNumQuads*4, resultRect);
        }
        
        /** @inheritDoc */
        public override function render(support:RenderSupport, parentAlpha:Number):void
        {
            if (mNumQuads)
            {
                if (mBatchable)
                    support.batchQuadBatch(this, parentAlpha);
                else
                {
                    support.finishQuadBatch();
                    support.raiseDrawCount();
                    renderCustom(support.mvpMatrix, alpha * parentAlpha, support.blendMode);
                }
            }
        }
        
        // compilation (for flattened sprites)
        
        /** Analyses an object that is made up exclusively of quads (or other containers)
         *  and creates a vector of QuadBatch objects representing it. This can be
         *  used to render the container very efficiently. The 'flatten'-method of the Sprite 
         *  class uses this method internally. */
        public static function compile(object:DisplayObject, 
                                       quadBatches:Vector.<QuadBatch>):void
        {
            compileObject(object, quadBatches, -1, new Matrix());
        }
        
        private static function compileObject(object:DisplayObject, 
                                              quadBatches:Vector.<QuadBatch>,
                                              quadBatchID:int,
                                              transformationMatrix:Matrix,
                                              alpha:Number=1.0,
                                              blendMode:String=null,
                                              ignoreCurrentFilter:Boolean=false):int
        {
            var i:int;
            var quadBatch:QuadBatch;
            var isRootObject:Boolean = false;
            var objectAlpha:Number = object.alpha;
            
            var container:DisplayObjectContainer = object as DisplayObjectContainer;
            var quad:Quad = object as Quad;
            var batch:QuadBatch = object as QuadBatch;
            var filter:FragmentFilter = object.filter;
            
            if (quadBatchID == -1)
            {
                isRootObject = true;
                quadBatchID = 0;
                objectAlpha = 1.0;
                blendMode = object.blendMode;
                ignoreCurrentFilter = true;
                if (quadBatches.length == 0) quadBatches.push(new QuadBatch());
                else quadBatches[0].reset();
            }
            
            if (filter && !ignoreCurrentFilter)
            {
                if (filter.mode == FragmentFilterMode.ABOVE)
                {
                    quadBatchID = compileObject(object, quadBatches, quadBatchID,
                                                transformationMatrix, alpha, blendMode, true);
                }
                
                quadBatchID = compileObject(filter.compile(object), quadBatches, quadBatchID,
                                            transformationMatrix, alpha, blendMode);
                
                if (filter.mode == FragmentFilterMode.BELOW)
                {
                    quadBatchID = compileObject(object, quadBatches, quadBatchID,
                        transformationMatrix, alpha, blendMode, true);
                }
            }
            else if (container)
            {
                var numChildren:int = container.numChildren;
                var childMatrix:Matrix = new Matrix();
                
                for (i=0; i<numChildren; ++i)
                {
                    var child:DisplayObject = container.getChildAt(i);
                    if (child.hasVisibleArea)
                    {
                        var childBlendMode:String = child.blendMode == BlendMode.AUTO ?
                                                    blendMode : child.blendMode;
                        childMatrix.copyFrom(transformationMatrix);
                        RenderSupport.transformMatrixForObject(childMatrix, child);
                        quadBatchID = compileObject(child, quadBatches, quadBatchID, childMatrix, 
                                                    alpha*objectAlpha, childBlendMode);
                    }
                }
            }
            else if (quad || batch)
            {
                var texture:Texture;
                var smoothing:String;
                var tinted:Boolean;
                var numQuads:int;
                
                if (quad)
                {
                    var image:Image = quad as Image;
                    texture = image ? image.texture : null;
                    smoothing = image ? image.smoothing : null;
                    tinted = quad.tinted;
                    numQuads = 1;
                }
                else
                {
                    texture = batch.mTexture;
                    smoothing = batch.mSmoothing;
                    tinted = batch.mTinted;
                    numQuads = batch.mNumQuads;
                }
                
                quadBatch = quadBatches[quadBatchID];
                
                if (quadBatch.isStateChange(tinted, alpha*objectAlpha, texture, 
                                            smoothing, blendMode, numQuads))
                {
                    quadBatchID++;
                    if (quadBatches.length <= quadBatchID) quadBatches.push(new QuadBatch());
                    quadBatch = quadBatches[quadBatchID];
                    quadBatch.reset();
                }
                
                if (quad)
                    quadBatch.addQuad(quad, alpha, texture, smoothing, transformationMatrix, blendMode);
                else
                    quadBatch.addQuadBatch(batch, alpha, transformationMatrix, blendMode);
            }
            else
            {
                throw new Error("Unsupported display object: " + getQualifiedClassName(object));
            }
            
            if (isRootObject)
            {
                // remove unused batches
                for (i=quadBatches.length-1; i>quadBatchID; --i)
                    quadBatches.pop().dispose();
            }
            
            return quadBatchID;
        }
        
        // properties
        
        /** Returns the number of quads that have been added to the batch. */
        public function get numQuads():int { return mNumQuads; }
        
        /** Indicates if any vertices have a non-white color or are not fully opaque. */
        public function get tinted():Boolean { return mTinted; }
        
        /** The texture that is used for rendering, or null for pure quads. Note that this is the
         *  texture instance of the first added quad; subsequently added quads may use a different
         *  instance, as long as the base texture is the same. */ 
        public function get texture():Texture { return mTexture; }
        
        /** The TextureSmoothing used for rendering. */
        public function get smoothing():String { return mSmoothing; }
        
        /** Indicates if the rgb values are stored premultiplied with the alpha value. */
        public function get premultipliedAlpha():Boolean { return mVertexData.premultipliedAlpha; }
        
        /** Indicates if the batch itself should be batched on rendering. This makes sense only
         *  if it contains only a small number of quads (we recommend no more than 16). Otherwise,
         *  the CPU costs will exceed any gains you get from avoiding the additional draw call.
         *  @default false */
        public function get batchable():Boolean { return mBatchable; }
        public function set batchable(value:Boolean):void { mBatchable = value; } 
        
        /** Indicates the number of quads for which space is allocated (vertex- and index-buffers).
         *  If you add more quads than what fits into the current capacity, the QuadBatch is
         *  expanded automatically. However, if you know beforehand how many vertices you need,
         *  you can manually set the right capacity with this method. */
        public function get capacity():int { return mVertexData.numVertices / 4; }
        public function set capacity(value:int):void
        {
            var oldCapacity:int = capacity;
            
            if (value == oldCapacity) return;
            else if (value == 0) throw new Error("Capacity must be > 0");
            else if (value > MAX_NUM_QUADS) value = MAX_NUM_QUADS;
            if (mNumQuads > value) mNumQuads = value;
            
            mVertexData.numVertices = value * 4;
            mIndexData.length = value * 6;
            
            for (var i:int=oldCapacity; i<value; ++i)
            {
                mIndexData[int(i*6  )] = i*4;
                mIndexData[int(i*6+1)] = i*4 + 1;
                mIndexData[int(i*6+2)] = i*4 + 2;
                mIndexData[int(i*6+3)] = i*4 + 1;
                mIndexData[int(i*6+4)] = i*4 + 3;
                mIndexData[int(i*6+5)] = i*4 + 2;
            }
			
			destroyBuffers();
			mSyncRequired = true;
        }
		
		private function getProgram(tinted:Boolean, pass:String):Program3D
		{
			var target:Starling = Starling.current;
			var programName:String = pass == RenderPass.MRT ? QUAD_PROGRAM_NAME : QUAD_PROGRAM_NAME_DEFERRED;
			
			if (mTexture)
				programName = getImageProgramName(tinted, mTexture.mipMapping, mTexture.repeat, mTexture.format, mSmoothing, pass);
			
			var program:Program3D = target.getProgram(programName);
			
			if (!program)
			{
				// this is the input data we'll pass to the shaders:
				// 
				// va0 -> position
				// va1 -> color
				// va2 -> texCoords
				// vc0 -> alpha
				// vc1 -> mvpMatrix
				// fs0 -> texture
				
				var vertexProgram:String;
				var fragmentProgram:String;
				
				if (!mTexture) // Quad-Shaders
				{
					if (pass == RenderPass.MRT)
					{						
						vertexProgram =
							Utils.joinProgramArray(
								[
									"m44 op, va0, vc1", // 4x4 matrix transform to output clipspace
									"mul v0, va1, vc0"  // multiply alpha (vc0) with color (va1)
								]
							);			
						
						// fc5, deferred quad normal [0.5, 0.5, 1.0, 0]
						// fc6, deferred quad specular/depth params [specPower, specIntensity, defaultDepth, 0.0]
						
						fragmentProgram = Utils.joinProgramArray(
							[
								// Diffuse render target
								'mov oc, v0',
								
								// Normal render target
								'mov oc1, fc5',
								
								// Depth render target
								// Write specular params to depth yz				
								'mov oc2.xyzw, fc6.zxyz'
							]
						);
					}
					else
					{
						vertexProgram =
							Utils.joinProgramArray(
								[
									"m44 op, va0, vc1", // 4x4 matrix transform to output clipspace
									"mul v0, va1, vc0"  // multiply alpha (vc0) with color (va1)
								]
							);               
						
						fragmentProgram =
							"mov oc, v0";  // output color
					}					
				}
				else // Image-Shaders
				{
					vertexProgram = Utils.joinProgramArray(
						[
							// 4x4 matrix transform to output clipspace
							'm44 op, va0, vc1',
							
							// Tint logic goes here
							'<tint_part>',
							
							// Pass texture coordinates to fragment program
							'mov v1, va2'
						]
					);
					
					fragmentProgram = Utils.joinProgramArray(
						[
							// Sample diffuse
							'tex ft1, v1, fs0 <sampler_flags>',
							
							// Tint logic goes here
							'<tint_part>',
							
							// Deferred pass logic goes here
							'<deferred_part>',
							
							// Output color
							'mov oc, ft1'
						]
					);
					
					// Tint
					
					vertexProgram = vertexProgram.replace(
						'<tint_part>',
						tinted ? TINT_VERTEX_PROGRAM_PART : ''
					);
					
					fragmentProgram = fragmentProgram.replace(
						'<tint_part>',
						tinted ? TINT_FRAGMENT_PROGRAM_PART : ''
					);
					
					// Deferred shading
					
					fragmentProgram = fragmentProgram.replace(
						'<sampler_flags>', 
						RenderSupport.getTextureLookupFlags(mTexture.format, mTexture.mipMapping, mTexture.repeat, smoothing)
					);								
					
					fragmentProgram = fragmentProgram.replace(
						'<deferred_part>',
						pass != RenderPass.MRT ? '' : DEFERRED_FRAGMENT_PROGRAM_PART
					);
				}
				
				program = target.registerProgramFromSource(programName, vertexProgram, fragmentProgram, pass == RenderPass.MRT ? 2 : 1);
			}
			
			return program;
		}
		
		// Tint program parts
		
		private static var TINT_VERTEX_PROGRAM_PART:String = Utils.joinProgramArray(
			[
				// Multiply alpha (vc0) with color (va1)
				'mul v0, va1, vc0'
			]
		);
		
		private static var TINT_FRAGMENT_PROGRAM_PART:String = Utils.joinProgramArray(
			[
				// Multiply color with texel color
				'mul ft1, ft1, v0'
			]
		);
		
		// Deferred program parts
		
		private static var DEFERRED_FRAGMENT_PROGRAM_PART:String = Utils.joinProgramArray(
			[
				// Sample normal					
				'tex ft4, v1, fs1 <sampler_flags>',
				
				// Sample depth					
				'tex ft3, v1, fs2 <sampler_flags>',
				
				// Set depth yz to specular power/intensity					
				'mov ft3.y, fc5.x',
				'mov ft3.z, fc5.y',
				
				// Mask normal/depth maps by diffuse map alpha
				// This is useful when user just passes rectangular single-color
				// normal map and wants to use it for the area covered by diffuse color
				'mul ft4, ft4, ft1.w',
				'mov oc1, ft4',
				'mul ft3, ft3, ft1.w',				
				
				'mov oc2, ft3'
			]
		);
        
        private static function getImageProgramName(tinted:Boolean, mipMap:Boolean=true, 
                                                    repeat:Boolean=false, format:String="bgra",
                                                    smoothing:String="bilinear", pass:String = RenderPass.NORMAL):String
        {
            var bitField:uint = 0;
            
            if (tinted) bitField |= 1;
            if (mipMap) bitField |= 1 << 1;
            if (repeat) bitField |= 1 << 2;
            
            if (smoothing == TextureSmoothing.NONE)
                bitField |= 1 << 3;
            else if (smoothing == TextureSmoothing.TRILINEAR)
                bitField |= 1 << 4;
            
            if (format == Context3DTextureFormat.COMPRESSED)
                bitField |= 1 << 5;
            else if (format == "compressedAlpha")
                bitField |= 1 << 6;
            
			if (pass != RenderPass.MRT)
				bitField |= 1 << 7;
			
            var name:String = sProgramNameCache[bitField];
            
            if (name == null)
            {
                name = "QB_i." + bitField.toString(16);
                sProgramNameCache[bitField] = name;
            }
            
            return name;
        }
    }
}