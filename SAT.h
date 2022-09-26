class SAT {
	
	private:
	
		int _thread = 4;
		int _forcus = 0;
		double _scale = 0.0;
		bool _mirror = true;
		
		int _width;
		int _height;
		
		dispatch_group_t _group = dispatch_group_create();
		dispatch_queue_t _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);
		
		unsigned int *_buf = nullptr;
		unsigned int *_dst = nullptr;
		unsigned int *_sum = nullptr;
		unsigned int *_radius = nullptr;
		
		inline unsigned char CLIP255(int v) { return ((v>0xFF)?0xFF:v); }

		void sumX(unsigned int *src, int begin, int end) {
			unsigned int *sum = this->_sum;
			int w = this->_width;
			int row = w+1;
			for(int i=begin; i<end; i++) {
				unsigned int a = 0;
				unsigned int b = 0;
				unsigned int g = 0;
				unsigned int r = 0;
				unsigned int *pSrc = src+i*w;
				unsigned int *pSum = sum+(((i+1)*row+(1))<<2);
				for(int j=0; j<w; j++) {
					unsigned int abrg = *pSrc++;
					if(abrg>>24) {
						a++;
						b+=(abrg>>16&0xFF);
						g+=(abrg>>8&0xFF);
						r+=(abrg&0xFF);
					}
					*pSum++=a;
					*pSum++=b;
					*pSum++=g;
					*pSum++=r;
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
			int w = this->_width;
			int h = this->_height;
			int row = w+1;
			for(int j=begin; j<end; j++) {
				unsigned int a = 0;
				unsigned int b = 0;
				unsigned int g = 0;
				unsigned int r = 0;
				for(int i=0; i<h; i++) {
					unsigned int *pSum = sum+(((i+1)*row+(j+1))<<2);
					*pSum++=(a+=*pSum);
					*pSum++=(b+=*pSum);
					*pSum++=(g+=*pSum);
					*pSum++=(r+=*pSum);
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
									
			int w = this->_width;
			int h = this->_height;
			
			int top = i-r;
			if(top<0) top = 0;
			
			int bottom=(i+r)+1;
			if(bottom>h) bottom = h;
			
			int left=j-r;
			if(left<0) left = 0;
			
			int right=(j+r)+1;
			if(right>w) right = w;
			
			unsigned int bgr = alpha<<24;
			unsigned int row = w+1;
							
			unsigned int *pBR = this->_sum+((bottom*row+right)<<2);
			unsigned int *pBL = this->_sum+((bottom*row+left)<<2);
			unsigned int *pTR = this->_sum+((top*row+right)<<2);
			unsigned int *pTL = this->_sum+((top*row+left)<<2);
			
			double weight = ((*pBR++)-(*pBL++)-(*pTR++)+(*pTL++));
			bgr|=((CLIP255(((*pBR++)-(*pBL++)-(*pTR++)+(*pTL++))/weight))<<16);
			bgr|=((CLIP255(((*pBR++)-(*pBL++)-(*pTR++)+(*pTL++))/weight))<<8);
			bgr|=((CLIP255(((*pBR++)-(*pBL++)-(*pTR++)+(*pTL++))/weight)));

			return bgr;
		}
	
		unsigned int calc(unsigned char alpha, int j, int i, int r, unsigned int wet) {
		
			int w = this->_width;
			int h = this->_height;
								
			unsigned int dry = 0x100-wet; 
			
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
				
			int row = w+1;
			unsigned int *pBR[2] = { 
				this->_sum+((bottom[0]*row+right[0])<<2), 
				this->_sum+((bottom[1]*row+right[1])<<2) 
			};
			unsigned int *pBL[2] = { 
				this->_sum+((bottom[0]*row+left[0])<<2), 
				this->_sum+((bottom[1]*row+left[1])<<2) 
			};
			unsigned int *pTR[2] = { 
				this->_sum+((top[0]*row+right[0])<<2), 
				this->_sum+((top[1]*row+right[1])<<2) 
			};
			unsigned int *pTL[2] = { 
				this->_sum+((top[0]*row+left[0])<<2), 
				this->_sum+((top[1]*row+left[1])<<2) 
			};
						
			double weight[2] = {
				(double)((*pBR[0]++)-(*pBL[0]++)-(*pTR[0]++)+(*pTL[0]++)),
				(double)((*pBR[1]++)-(*pBL[1]++)-(*pTR[1]++)+(*pTL[1]++)),
			};
			
			unsigned int bgr = alpha<<24;
			for(int k=0; k<3; k++) {
				unsigned int color = CLIP255(((*pBR[0]++)-(*pBL[0]++)-(*pTR[0]++)+(*pTL[0]++))/weight[0])*dry;
				color+=CLIP255(((*pBR[1]++)-(*pBL[1]++)-(*pTR[1]++)+(*pTL[1]++))/weight[1])*wet;
				color>>=8;
				bgr|=(color<<(0x10-(k<<3)));
			}
			
			return bgr;
		}
					
		void blur(unsigned int *dst, unsigned int *src, int begin, int end) {
			int w = this->_width;
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
							unsigned int wet = r&0xFF;
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
			int row = this->_width+1;
			int col = this->_height+1;
			unsigned int *pSum = this->_sum;
			for(int k=0; k<row*4; k++) pSum[k] = 0;
			for(int k=0; k<col; k++) {
				pSum[(k*row)*4+0] = pSum[(k*row)*4+1] = pSum[(k*row)*4+2] = pSum[(k*row)*4+3] = 0;
			}
		}
			
		void radius(unsigned char *depth, int begin, int end) {
			int w = this->_width;
			double s = this->_scale;
			double f = (this->_forcus==0)?0:(this->_forcus*s);
			for(int i=begin; i<end; i++) {
				unsigned int *pRadius = this->_radius+i*w;
				unsigned char *pDepth = depth+i*w;
				for(int j=0; j<w; j++) {
					float v = (*pDepth++)-DEPTH_OFFSET;
					if(v<0) v = 0;
					v*=s;
					v+=f;
					if(v<0) v = (this->_mirror)?-v:0;
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
				
		static constexpr int DEPTH_OFFSET = 4;
		static constexpr double DEPTH_SCALE = 16.0;
		
		SAT(int w, int h) {
			this->_width = w;
			this->_height = h;
			unsigned int row = w+1;
			unsigned int col = h+1;
			this->_buf = new unsigned int[w*h];
			this->_dst = new unsigned int[w*h];
			this->_sum = new unsigned int[(row*col)<<2];
			this->_radius = new unsigned int[w*h];
			for(int k=0; k<w*h; k++) this->_radius[k] = 0*0x100;
			this->_scale = 1.0/DEPTH_SCALE;
			this->erase();
		}
		
		~SAT() {
			delete[] this->_radius;
			delete[] this->_sum;
			delete[] this->_dst;
			delete[] this->_buf;
		}
		
		int width() { return this->_width; };
		int height() { return this->_height; };
			
		unsigned int *bytes() { return this->_dst; }
		
		void thread(int t) { this->_thread = (t>=8)?8:(t<=1)?1:t; }

		void mirror(bool v) { this->_mirror = v; }
		void forcus(int v) { this->_forcus = v; }
		void scale(double v) { this->_scale = v; }
			
		void blur(unsigned int *src) {
			this->sumX(src,this->_thread);
			this->sumY(this->_thread);
			this->blur(this->_buf,src,this->_thread);
			this->sumX(this->_buf,this->_thread);
			this->sumY(this->_thread);
			this->blur(this->_dst,this->_buf,this->_thread);
		}
		
		void blur(unsigned int *src, unsigned char *depth) {
			this->radius(depth,this->_thread);
			this->blur(src);
		}
};