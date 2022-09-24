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
#define CLAMP255(v) ((v>0xFF)?0xFF:(v<0)?0:v)
#define BGR 3

void sumX(unsigned int *sum, unsigned int *src, int w, int h, int begin, int end) {
	unsigned int bgr[BGR] = {0,0,0};
	for(int i=begin; i<end; i++) {
		for(int n=0; n<BGR; n++) bgr[n]=0;
		unsigned int *pSum = sum+i*w*BGR;
		unsigned int *pSrc = src+i*w;
		for(int j=0; j<w; j++) {
			unsigned int pixel = *pSrc++;
			for(int n=0; n<BGR; n++) {
				*pSum++=(bgr[n]+=(pixel>>(0x10-(n<<3)))&0xFF);
			}
		}
	}
}

void sumX(unsigned int *sum, unsigned int *src, int w, int h, int thread=8) {
	
	dispatch_group_t _group = dispatch_group_create();
	dispatch_queue_t _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);
	
	int col = h/thread;
	
	for(int k=0; k<thread; k++) {
		if(k==thread-1) {
			dispatch_group_async(_group,_queue,^{
				sumX(sum,src,w,h,col*k,h);
			});
		}
		else {
			dispatch_group_async(_group,_queue,^{
				sumX(sum,src,w,h,col*k,col*(k+1));
			});
		}
	}
	
	dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
}

void sumY(unsigned int *sum, int w, int h, int begin, int end) {
	unsigned int bgr[BGR] = {0,0,0};
	for(int j=begin; j<end; j++) {
		for(int n=0; n<BGR; n++) bgr[n]=0;
		for(int i=0; i<h; i++) {
			unsigned int addr = (i*w+j)*BGR;
			for(int n=0; n<BGR; n++) {
				sum[addr++]=(bgr[n]+=sum[addr]);
			}
		}
	}
}

void sumY(unsigned int *sum, int w, int h, int thread=8) {
	
	dispatch_group_t _group = dispatch_group_create();
	dispatch_queue_t _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);
	
	int row = w/thread;

	for(int k=0; k<thread; k++) {
		if(k==thread-1) {
			dispatch_group_async(_group,_queue,^{
				sumY(sum,w,h,row*k,w);
			});
		}
		else {
			dispatch_group_async(_group,_queue,^{
				sumY(sum,w,h,row*k,row*(k+1));
			});
		}
	}
	
	dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
}

static unsigned int blur(unsigned int *sum, int w, int h, int j, int i, int r) {
	
	unsigned int bgr = 0xFF000000;
	
	int top = i-(r+1);
	if(top<0) top = 0;
	
	int bottom=i+r;
	if(bottom>h-1) bottom = h-1;

	int left=j-(r+1);
	if(left<0) left = 0;

	int right=j+r;
	if(right>w-1) right = w-1; 	
	
	double area = 1.0/(double)((right-left)*(bottom-top));
	
	int TL = (top*w+left)*BGR;
	int TR = (top*w+right)*BGR;
	int BL = (bottom*w+left)*BGR;
	int BR = (bottom*w+right)*BGR;
	
	for(int n=0; n<BGR; n++) {
		bgr |= ((unsigned int)CLIP255((sum[BR+n]-sum[BL+n]-sum[TR+n]+sum[TL+n])*area))<<(0x10-(n<<3));
	}
	
	return bgr;
}

static unsigned int blur(unsigned int *sum, int w, int h, int j, int i, int r, int wet) {
	
	unsigned int bgr = 0xFF000000;

	int dry = 0x100-wet; 
	
	int top[2] = {
		i-(r+1),
		i-((r+1)+1),
	};
	for(int n=0; n<2; n++) { if(top[n]<0) top[n] = 0; }
		
	int bottom[2] = {
		i+r,
		i+(r+1)
	};
	for(int n=0; n<2; n++) { if(bottom[n]>h-1) bottom[n] = h-1; }
		
	int left[2] = {
		j-(r+1),
		j-((r+1)+1)
	};
	for(int n=0; n<2; n++) { if(left[n]<0) left[n] = 0; }

	int right[2] = {
		j+r,
		j+(r+1)
	};
	for(int n=0; n<2; n++) { if(right[n]>w-1) right[n] = w-1; }
	
	double area[2] = {
		1.0/(double)((right[0]-left[0])*(bottom[0]-top[0])),
		1.0/(double)((right[1]-left[1])*(bottom[1]-top[1]))
	};
	
	int TL[2] = {
		(top[0]*w+left[0])*BGR,
		(top[1]*w+left[1])*BGR,
	};
	int TR[2] = { 
		(top[0]*w+right[0])*BGR,
		(top[1]*w+right[1])*BGR
	};
	int BL[2] = { 
		(bottom[0]*w+left[0])*BGR,
		(bottom[1]*w+left[1])*BGR
	};
	int BR[2] = { 
		(bottom[0]*w+right[0])*BGR,
		(bottom[1]*w+right[1])*BGR
	};
		
	for(int n=0; n<BGR; n++) {
		
		unsigned int color = CLIP255((sum[BR[0]+n]-sum[BL[0]+n]-sum[TR[0]+n]+sum[TL[0]+n])*area[0])*dry;
		color+=CLIP255((sum[BR[1]+n]-sum[BL[1]+n]-sum[TR[1]+n]+sum[TL[1]+n])*area[1])*wet;
		color>>=8;
		
		bgr |= color<<(0x10-(n<<3));
	}
		
	return bgr;
}

void blur(unsigned int *dst, unsigned int *src, unsigned int *sum, unsigned int *radius, int w, int h, int begin, int end) {

	unsigned char bgr[3] = {0,0,0};

	for(int i=begin; i<end; i++) {
		for(int j=0; j<w; j++) {
			
			unsigned int addr = i*w+j;
			
			if(radius[addr]==0) {
				dst[addr] = src[addr];
			}
			else {
				
				int wet = radius[addr]&0xFF;
				if(wet==0) {
					dst[addr] = blur(sum,w,h,j,i,(radius[addr])>>8);
				}
				else {
					dst[addr] = blur(sum,w,h,j,i,(radius[addr])>>8,wet);
				}
			}
		}
	}
}

void blur(unsigned int *dst, unsigned int *src, unsigned int *sum, unsigned int *radius, int w, int h, int thread=8) {
	
	dispatch_group_t _group = dispatch_group_create();
	dispatch_queue_t _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);

	int col = h/thread;
	
	for(int k=0; k<thread; k++) {
		if(k==thread-1) {
			dispatch_group_async(_group,_queue,^{
				blur(dst,src,sum,radius,w,h,col*k,h);
			});
		}
		else {
			dispatch_group_async(_group,_queue,^{
				blur(dst,src,sum,radius,w,h,col*k,col*(k+1));
			});
		}
	}
	
	dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
}

int main(int argc, char *argv[]) {

	@autoreleasepool {
		
		const int THREAD = 1;
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

			unsigned int *sum = new unsigned int[w*h*BGR];
			unsigned int *depth = (unsigned int *)stb_image::stbi_load("./depth.png",info,info+1,info+2,4);

			unsigned int *radius = new unsigned int[w*h];
			for(int i=0; i<h; i++) {
				for(int j=0; j<w; j++) {
					unsigned int addr = (i*w+j);
					float v = (depth[addr]&0xFF)-DEPTH_OFFSET;
					if(v<0) v = 0;
					v/=(DEPTH_SCALE);
					v*=5.0;
					v-=4.0;
					if(MIRROR) { if(v<0) v = -v;}
					else { if(v<0) v = 0; }
					v*=0x100;
					radius[addr] = v;
				}
			}
			
			int bgr[BGR] = {0,0,0};

double then = CFAbsoluteTimeGetCurrent();
			
			sumX(sum,src,w,h,THREAD);
			sumY(sum,w,h,THREAD);
			blur(buf,src,sum,radius,w,h,THREAD);
			
			sumX(sum,buf,w,h,THREAD);
			sumY(sum,w,h,THREAD);
			blur(dst,buf,sum,radius,w,h,THREAD);

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
	