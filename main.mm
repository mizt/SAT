#import <Foundation/Foundation.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
namespace stb_image {
	#import "./libs/stb_image.h"
	#import "./libs/stb_image_write.h"
}

#define CLIP255(v) ((v>0xFF)?0xFF:v)
#define BGR 3
#define SHIFT(v) (0x10-(v<<3))

namespace SAT {
	
	dispatch_group_t _group = dispatch_group_create();
	dispatch_queue_t _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);
	
	void sumX(unsigned int *sum, unsigned int *area, unsigned int *src, int w, int h, int begin, int end) {
		int row = w+1;
		unsigned int bgr[BGR] = {0,0,0};
		for(int i=begin; i<end; i++) {
			int alpha = 0;
			for(int n=0; n<BGR; n++) bgr[n]=0;
			unsigned int *pSrc = src+i*w;
			unsigned int *pSum = sum+((i+1)*row+1)*BGR;
			unsigned int *pArea = area+((i+1)*row+1);
			for(int j=0; j<w; j++) {
				unsigned int abrg = *pSrc++;
				*pArea++=(alpha+=((abrg>>24)==0)?0:1);
				for(int n=0; n<BGR; n++) *pSum++=(bgr[n]+=(abrg>>SHIFT(n))&0xFF);
			}
		}
	}
	
	void sumX(unsigned int *sum, unsigned int *area, unsigned int *src, int w, int h, int thread=8) {
		int col = h/thread;	
		for(int k=0; k<thread; k++) {
			if(k==thread-1) {
				dispatch_group_async(_group,_queue,^{
					sumX(sum,area,src,w,h,col*k,h);
				});
			}
			else {
				dispatch_group_async(_group,_queue,^{
					sumX(sum,area,src,w,h,col*k,col*(k+1));
				});
			}
		}
		dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
	}
	
	void sumY(unsigned int *sum, unsigned int *area, int w, int h, int begin, int end) {
		int row = w+1;
		unsigned int bgr[BGR] = {0,0,0};
		for(int j=begin; j<end; j++) {
			for(int n=0; n<BGR; n++) bgr[n]=0;
			int alpha = 0;
			for(int i=0; i<h; i++) {
				unsigned int addr = ((i+1)*row+(j+1));
				area[addr]=(alpha+=area[addr]);
				addr = ((i+1)*row+(j+1))*BGR;
				for(int n=0; n<BGR; n++) {
					sum[addr++]=(bgr[n]+=sum[addr]);
				}
			}
		}
	}
	
	void sumY(unsigned int *sum, unsigned int *area, int w, int h, int thread=8) {
		int row = w/thread;
		for(int k=0; k<thread; k++) {
			if(k==thread-1) {
				dispatch_group_async(_group,_queue,^{
					sumY(sum,area,w,h,row*k,w);
				});
			}
			else {
				dispatch_group_async(_group,_queue,^{
					sumY(sum,area,w,h,row*k,row*(k+1));
				});
			}
		}
		
		dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
	}
	
	unsigned int blur(unsigned int *sum, unsigned int *area, int w, int h, int j, int i, int r) {
		
		unsigned int bgr = 0xFF000000;
		
		int row = w+1;
		
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
		
		double weight = 1.0/(area[BR]-area[BL]-area[TR]+area[TL]);
		
		TL*=BGR;
		TR*=BGR;
		BL*=BGR;
		BR*=BGR;
		
		for(int n=0; n<BGR; n++) {
			bgr|=(((unsigned int)CLIP255((sum[BR+n]-sum[BL+n]-sum[TR+n]+sum[TL+n])*weight))<<SHIFT(n));
		}
		
		return bgr;
	}
	
	unsigned int blur(unsigned int *sum, unsigned int *area, int w, int h, int j, int i, int r, int wet) {
		
		int row = w+1;
		
		unsigned int bgr = 0xFF000000;
		
		int dry = 0x100-wet; 
		
		int top[2] = {
			i-r,
			i-(r+1)
		};
		for(int n=0; n<2; n++) { if(top[n]<0) top[n] = 0; }
			
		int bottom[2] = {
			(i+r)+1,
			(i+(r+1))+1
		};
		for(int n=0; n<2; n++) { if(bottom[n]>h) bottom[n] = h; }
				
		int left[2] = {
			j-r,
			j-(r+1)
		};
		for(int n=0; n<2; n++) { if(left[n]<0) left[n] = 0; }
					
		int right[2] = {
			(j+r)+1,
			(j+(r+1))+1
		};
		for(int n=0; n<2; n++) { if(right[n]>w) right[n] = w; }
						
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
			1.0/(double)(area[BR[0]]-area[BL[0]]-area[TR[0]]+area[TL[0]]),
			1.0/(double)(area[BR[1]]-area[BL[1]]-area[TR[1]]+area[TL[1]])
		};
		
		for(int n=0; n<2; n++) {
			TL[n]*=BGR;
			TR[n]*=BGR;
			BL[n]*=BGR;
			BR[n]*=BGR;
		}
		
		for(int n=0; n<BGR; n++) {
			unsigned int color = CLIP255((sum[BR[0]+n]-sum[BL[0]+n]-sum[TR[0]+n]+sum[TL[0]+n])*weight[0])*dry;
			color+=CLIP255((sum[BR[1]+n]-sum[BL[1]+n]-sum[TR[1]+n]+sum[TL[1]+n])*weight[1])*wet;
			color>>=8;
			bgr|=(color<<SHIFT(n));
		}
		
		return bgr;
	}
					
		void blur(unsigned int *dst, unsigned int *area, unsigned int *src, unsigned int *sum, unsigned int *radius, int w, int h, int begin, int end) {
			
			for(int i=begin; i<end; i++) {
				unsigned int addr = i*w;
				for(int j=0; j<w; j++) {
					int r = radius[addr];
					if(r==0) {
						dst[addr] = src[addr];
					}
					else {
						int wet = r&0xFF;
						if(wet==0) {
							dst[addr] = blur(sum,area,w,h,j,i,r>>8);
						}
						else {
							dst[addr] = blur(sum,area,w,h,j,i,r>>8,wet);
						}
					}
					addr++;
				}
			}
		}
					
	void blur(unsigned int *dst, unsigned int *area, unsigned int *src, unsigned int *sum, unsigned int *radius, int w, int h, int thread=8) {
		int col = h/thread;
		for(int k=0; k<thread; k++) {
			if(k==thread-1) {
				dispatch_group_async(_group,_queue,^{
					blur(dst,area,src,sum,radius,w,h,col*k,h);
				});
			}
			else {
				dispatch_group_async(_group,_queue,^{
					blur(dst,area,src,sum,radius,w,h,col*k,col*(k+1));
				});
			}
		}
		dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
	}
					
	void erase(unsigned int *area, unsigned int *sum, int w, int h) {
		int row = w+1;
		for(int k=0; k<(w+1); k++) area[k] = 0;
		for(int k=0; k<(h+1); k++) area[k*row] = 0;	
		for(int k=0; k<(w+1)*BGR; k++) sum[k] = 0;
		for(int k=0; k<(h+1); k++) sum[(k*row)*BGR+0] = sum[(k*row)*BGR+1] = sum[(k*row)*BGR+2] = 0;
	}
};



int main(int argc, char *argv[]) {

	@autoreleasepool {
		
		const int THREAD = 4;
		const bool MIRROR = true;
		
		const int DEPTH_OFFSET = 4;
		const float DEPTH_SCALE = 16.0;
		
		int info[3];	
		unsigned int *src = (unsigned int *)stb_image::stbi_load("./texture.jpg",info,info+1,info+2,4);
		
		if(src) {
			
			const int w = info[0];
			const int h = info[1];
			unsigned int *buf = new unsigned int[w*h];
			unsigned int *dst = new unsigned int[w*h];

			unsigned int *area = new unsigned int[(w+1)*(h+1)];
			unsigned int *sum = new unsigned int[(w+1)*(h+1)*BGR];
					
			unsigned int *depth = (unsigned int *)stb_image::stbi_load("./depth.png",info,info+1,info+2,4);

			unsigned int *radius = new unsigned int[w*h];
			for(int i=0; i<h; i++) {
				for(int j=0; j<w; j++) {
					unsigned int addr = (i*w+j);
					float v = (depth[addr]&0xFF)-DEPTH_OFFSET;
					if(v<0) v = 0;
					v/=(DEPTH_SCALE);
					if(MIRROR) { if(v<0) v = -v;}
					else { if(v<0) v = 0; }
					v*=0x100;
					radius[addr] = v;
				}
			}
			
			int bgr[BGR] = {0,0,0};


double then = CFAbsoluteTimeGetCurrent();

			SAT::erase(area,sum,w,h);
			SAT::sumX(sum,area,src,w,h,THREAD);
			SAT::sumY(sum,area,w,h,THREAD);
			SAT::blur(buf,area,src,sum,radius,w,h,THREAD);
			
			SAT::erase(area,sum,w,h);
			SAT::sumX(sum,area,buf,w,h,THREAD);
			SAT::sumY(sum,area,w,h,THREAD);
			SAT::blur(dst,area,buf,sum,radius,w,h,THREAD);

NSLog(@"%f",CFAbsoluteTimeGetCurrent()-then);
			
			stb_image::stbi_write_png("./blur.png",w,h,4,(void const*)dst,w<<2);
			
			delete[] radius;
			delete[] depth;
			delete[] sum;
			delete[] dst;
			delete[] buf;
			delete[] src;
		}
	}
}
	