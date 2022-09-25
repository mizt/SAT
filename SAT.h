#define CLIP255(v) ((v>0xFF)?0xFF:v)
#define BGR 3
#define SHIFT(v) (0x10-(v<<3))

class SAT {
	
	private:
	
		const int THREAD = 4;
		const bool MIRROR = true;
		
		const int DEPTH_OFFSET = 4;
		const float DEPTH_SCALE = 16.0;
		
		int _width;
		int _height;
		
		dispatch_group_t _group = dispatch_group_create();
		dispatch_queue_t _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);
		
		unsigned int *_buf = nullptr;
		unsigned int *_dst = nullptr;
		
		unsigned int *_area = nullptr;
		unsigned int *_sum = nullptr;

		unsigned int *_radius = nullptr;

		void sumX(unsigned int *src, int begin, int end) {
			
			unsigned int *sum = this->_sum;
			unsigned int *area = this->_area;
			int w = this->_width;
			int h = this->_height;
			int row = w+1;
			unsigned int bgr[BGR] = {0,0,0};
			for(int i=begin; i<end; i++) {
				unsigned int addr = (i+1)*row+1;
				unsigned int alpha = 0;
				bgr[0]=bgr[1]=bgr[2]=0;
				unsigned int *pSrc = src+i*w;
				unsigned int *pSum = sum+addr*BGR;
				unsigned int *pArea = area+addr;
				for(int j=0; j<w; j++) {
					unsigned int abrg = *pSrc++;
					if((abrg>>24)==0) {
						*pArea++=alpha;
						for(int n=0; n<BGR; n++) *pSum++=bgr[n];
					}
					else {
						*pArea++=(++alpha);
						for(int n=0; n<BGR; n++) *pSum++=(bgr[n]+=(abrg>>SHIFT(n))&0xFF);
					}
				}
			}
		}
		
		void sumX(unsigned int *src,int thread=8) {
			int col = this->_height/thread;	
			for(int k=0; k<thread; k++) {
				if(k==thread-1) {
					dispatch_group_async(_group,_queue,^{
						sumX(src,col*k,this->_height);
					});
				}
				else {
					dispatch_group_async(_group,_queue,^{
						sumX(src,col*k,col*(k+1));
					});
				}
			}
			dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
		}
		
		void sumY(int begin, int end) {
			unsigned int *sum = this->_sum;
			unsigned int *area = this->_area;
			int w = this->_width;
			int h = this->_height;
			int row = w+1;
			unsigned int bgr[BGR] = {0,0,0};
			for(int j=begin; j<end; j++) {
				bgr[0]=bgr[1]=bgr[2]=0;
				unsigned int alpha = 0;
				for(int i=0; i<h; i++) {
					unsigned int addr = (i+1)*row+(j+1);
					unsigned int *pArea = area+addr;
					unsigned int *pSum = sum+addr*BGR;
					*pArea=(alpha+=*pArea);
					for(int n=0; n<BGR; n++) *pSum++=(bgr[n]+=*pSum);
				}
			}
		}
		
		void sumY(int thread=8) {
			int row = this->_width/thread;
			for(int k=0; k<thread; k++) {
				if(k==thread-1) {
					dispatch_group_async(_group,_queue,^{
						sumY(row*k,this->_width);
					});
				}
				else {
					dispatch_group_async(_group,_queue,^{
						sumY(row*k,row*(k+1));
					});
				}
			}
			dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
		}
		
		unsigned int calc(unsigned char alpha, int j, int i, int r) {
			
			unsigned int *pSum = this->_sum;
			unsigned int *pArea = this->_area;
						
			int w = this->_width;
			int h = this->_height;
			int row = w+1;
			
			unsigned int bgr = alpha<<24;
			
			int top = i-r;
			if(top<0) top = 0;
			
			int bottom=(i+r)+1;
			if(bottom>h) bottom = h;
			
			int left=j-r;
			if(left<0) left = 0;
			
			int right=(j+r)+1;
			if(right>w) right = w;
			
			int TL = (top*row+left);
			int TR = (top*row+right);
			int BL = (bottom*row+left);
			int BR = (bottom*row+right);
			
			double weight = 1.0/(pArea[BR]-pArea[BL]-pArea[TR]+pArea[TL]);
			
			TL*=BGR;
			TR*=BGR;
			BL*=BGR;
			BR*=BGR;
			
			for(int n=0; n<BGR; n++) {
				bgr|=(((unsigned int)CLIP255((pSum[BR+n]-pSum[BL+n]-pSum[TR+n]+pSum[TL+n])*weight))<<SHIFT(n));
			}
			
			return bgr;
		}
	
		unsigned int calc(unsigned char alpha, int j, int i, int r, int wet) {
		
			unsigned int *pSum = this->_sum;
			unsigned int *pArea = this->_area;
			
			int w = this->width();
			int h = this->height();
		
			int row = w+1;
			
			unsigned int bgr = alpha<<24;
			
			int dry = 0x100-wet; 
			
			int top[2] = {
				i-r,
				i-(r+1)
			};
			for(int n=0; n<2; n++) { if(top[n]<0) top[n]=0; }
			
			int bottom[2] = {
				(i+r)+1,
				(i+(r+1))+1
			};
			for(int n=0; n<2; n++) { if(bottom[n]>h) bottom[n]=h; }
				
			int left[2] = {
				j-r,
				j-(r+1)
			};
			for(int n=0; n<2; n++) { if(left[n]<0) left[n]=0; }
				
			int right[2] = {
				(j+r)+1,
				(j+(r+1))+1
			};
			for(int n=0; n<2; n++) { if(right[n]>w) right[n]=w; }
				int TL[2] = {
					(top[0]*row+left[0]),
					(top[1]*row+left[1])
				};
				int TR[2] = { 
					(top[0]*row+right[0]),
					(top[1]*row+right[1])
				};
				int BL[2] = { 
					(bottom[0]*row+left[0]),
					(bottom[1]*row+left[1])
				};
				int BR[2] = { 
					(bottom[0]*row+right[0]),
					(bottom[1]*row+right[1])
				};
				double weight[2] = {
					1.0/(double)(pArea[BR[0]]-pArea[BL[0]]-pArea[TR[0]]+pArea[TL[0]]),
					1.0/(double)(pArea[BR[1]]-pArea[BL[1]]-pArea[TR[1]]+pArea[TL[1]])
				};
				for(int n=0; n<2; n++) {
					TL[n]*=BGR;
					TR[n]*=BGR;
					BL[n]*=BGR;
					BR[n]*=BGR;
				}
				for(int n=0; n<BGR; n++) {
					unsigned int color = CLIP255((pSum[BR[0]+n]-pSum[BL[0]+n]-pSum[TR[0]+n]+pSum[TL[0]+n])*weight[0])*dry;
					color+=CLIP255((pSum[BR[1]+n]-pSum[BL[1]+n]-pSum[TR[1]+n]+pSum[TL[1]+n])*weight[1])*wet;
					color>>=8;
					bgr|=(color<<SHIFT(n));
				}
				return bgr;
			}
					
			void blur(unsigned int *dst, unsigned int *src, int begin, int end) {
				int w = this->width();
				int h = this->height();
				for(int i=begin; i<end; i++) {
					unsigned int *pRadius = this->_radius+i*w;
					unsigned int *pSrc = src+i*w;
					unsigned int *pDst = dst+i*w;
					for(int j=0; j<w; j++) {
						unsigned int pixel = *pSrc++; 
						unsigned char alpha = pixel>>24;
						if(alpha==0) {
							*pDst++ = 0x0;
						}
						else {
							int r = *pRadius;
							if(r==0) {
								*pDst++ = pixel;
							}
							else {
								int wet = r&0xFF;
								if(wet==0) {
									*pDst++ = calc(alpha,j,i,r>>8);
								}
								else {
									*pDst++ = calc(alpha,j,i,r>>8,wet);
								}
							}
						}
						pRadius++;
					}
				}
			}
					
			void blur(unsigned int *dst, unsigned int *src, int thread=8) {
				int col = this->_height/thread;
				for(int k=0; k<thread; k++) {
					if(k==thread-1) {
						dispatch_group_async(_group,_queue,^{
							blur(dst,src,col*k,this->_height);
						});
					}
					else {
						dispatch_group_async(_group,_queue,^{
							blur(dst,src,col*k,col*(k+1));
						});
					}
				}
				dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
			}
					
			void erase() {
				int w = this->width();
				int h = this->height();
				int row = w+1;
				int col = h+1;
				unsigned int *pArea = this->_area;
				unsigned int *pSum = this->_sum;
				for(int k=0; k<row; k++) pArea[k] = 0;
				for(int k=0; k<col; k++) pArea[k*row] = 0;
				for(int k=0; k<row*BGR; k++) pSum[k] = 0;
				for(int k=0; k<col; k++) pSum[(k*row)*BGR+0] = pSum[(k*row)*BGR+1] = pSum[(k*row)*BGR+2] = 0;
			}
				
			void radius(unsigned char *depth, int begin, int end) {
				
				int w = this->width();
				int h = this->height();
				
				for(int i=begin; i<end; i++) {
					unsigned int *pRadius = this->_radius+i*w;
					unsigned char *pDepth = depth+i*w;
					for(int j=0; j<w; j++) {
						float v = (*pDepth++)-DEPTH_OFFSET;
						if(v<0) v = 0;
						v/=(DEPTH_SCALE);
						if(v<0) v = (MIRROR)?-v:0;
						*pRadius++=v*0x100;
					}
				}
			}
				
			void radius(unsigned char *depth, int thread=8) {
				int col = this->_height/thread;
				for(int k=0; k<thread; k++) {
					if(k==thread-1) {
						dispatch_group_async(_group,_queue,^{
							this->radius(depth,col*k,this->_height);

						});
					}
					else {
						dispatch_group_async(_group,_queue,^{
							this->radius(depth,col*k,col*(k+1));
						});
					}
				}
				dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
			}
				
		public:
			
			SAT(int w, int h) {
				
				this->_width = w;
				this->_height = h; 
				
				unsigned int row = w+1;
				unsigned int col = h+1;
				
				this->_buf = new unsigned int[w*h];
				this->_dst = new unsigned int[w*h];
				
				this->_area = new unsigned int[row*col];
				this->_sum = new unsigned int[row*col*BGR];
				
				this->_radius = new unsigned int[w*h];
				for(int k=0; k<w*h; k++) this->_radius[k] = 0*0x100;
			}
			
			~SAT() {
				delete[] this->_radius;
				delete[] this->_area;
				delete[] this->_sum;
				delete[] this->_dst;
				delete[] this->_buf;
			}
			
			int width() { return this->_width; };
			int height() { return this->_height; };
				
			unsigned int *bytes() { return this->_dst; }
				
			void blur(unsigned int *src) {
				this->erase();
				this->sumX(src,THREAD);
				this->sumY(THREAD);
				this->blur(this->_buf,src,THREAD);
				
				this->erase();
				this->sumX(this->_buf,THREAD);
				this->sumY(THREAD);
				this->blur(this->_dst,this->_buf,THREAD);
			}
			
			void blur(unsigned int *src, unsigned char *depth) {
				this->radius(depth,THREAD);
				this->blur(src);
			}
};