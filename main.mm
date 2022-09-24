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

static void blur(unsigned char *bgr, unsigned int *sum, int w, int h, int j, int i, int r) {
	
	int top = i-(r+1);
	if(top<0) top = 0;
	
	int bottom=i+r;
	if(bottom>h-1) bottom = h-1;

	int left=j-(r+1);
	if(left<0) left = 0;

	int right=j+r;
	if(right>w-1) right = w-1; 	
	
	double area = 1.0/(double)((right-left)*(bottom-top));
	
	unsigned int TL = (top*w+left)*BGR;
	unsigned int TR = (top*w+right)*BGR;
	unsigned int BL = (bottom*w+left)*BGR;
	unsigned int BR = (bottom*w+right)*BGR;
	
	bgr[0] = CLIP255((sum[BR]-sum[BL]-sum[TR]+sum[TL])*area);
	bgr[1] = CLIP255((sum[BR+1]-sum[BL+1]-sum[TR+1]+sum[TL+1])*area);
	bgr[2] = CLIP255((sum[BR+2]-sum[BL+2]-sum[TR+2]+sum[TL+2])*area);
}

void blur(unsigned int *dst, unsigned int *src, unsigned int *sum, unsigned int *radius, int w, int h, int begin, int end) {

	unsigned char bgr[3] = {0,0,0};

	for(int i=begin; i<end; i++) {
		for(int j=0; j<w; j++) {
			
			unsigned int addr = i*w+j;
			
			unsigned int r = (radius[addr])>>8;
			
			if(r==0) {
				dst[addr] = src[addr];
			}
			else {
				
				blur(bgr,sum,w,h,j,i,r);
				
				unsigned char blue = bgr[0]; 
				unsigned char green = bgr[1]; 
				unsigned char red = bgr[2]; 
				
				dst[i*w+j] = 0xFF000000|blue<<16|green<<8|red;
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
		
		const int THREAD = 3;
		
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
					int v = (depth[addr]&0xFF)-DEPTH_OFFSET;
					v/=DEPTH_SCALE;
					v*=0x100;
					if(v<0) v = 0;
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
	