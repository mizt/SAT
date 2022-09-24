#import <Foundation/Foundation.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
namespace stb_image {
	#import "./libs/stb_image.h"
	#import "./libs/stb_image_write.h"
}

#define CLAMP255(v) ((v>0xFF)?0xFF:(v<0)?0:v)
#define BGR 3

void sumX(unsigned int *sum, unsigned int *src, int w, int h, int begin, int end) {
	unsigned int bgr[BGR] = {0,0,0};
	for(int i=begin; i<end; i++) {
		for(int n=0; n<BGR; n++) bgr[n]=0;
		for(int j=0; j<w; j++) {
			unsigned int pixel = src[i*w+j];
			unsigned int addr = (i*w+j)*BGR;
			for(int n=0; n<BGR; n++) {
				sum[addr++] = (bgr[n]+=((pixel>>(0x10-(n<<3)))&0xFF));
			}
		}
	}
}

void sumX(unsigned int *sum, unsigned int *src, int w, int h) {
	
	dispatch_group_t _group = dispatch_group_create();
	dispatch_queue_t _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);
	
	dispatch_group_async(_group,_queue,^{
		sumX(sum,src,w,h,0,h>>1);
	});
	dispatch_group_async(_group,_queue,^{
		sumX(sum,src,w,h,(h>>2)*1,(h>>2)*2);
	});
	
	dispatch_group_async(_group,_queue,^{
		sumX(sum,src,w,h,(h>>2)*2,(h>>2)*3);
	});
	
	dispatch_group_async(_group,_queue,^{
		sumX(sum,src,w,h,(h>>2)*3,h);
	});
	
	dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);	
}

void sumY(unsigned int *sum, int w, int h, int begin, int end) {
	unsigned int bgr[BGR] = {0,0,0};
	for(int j=begin; j<end; j++) {
		for(int n=0; n<BGR; n++) bgr[n]=0;
		for(int i=0; i<h; i++) {
			unsigned int addr = (i*w+j)*BGR;
			for(int n=0; n<BGR; n++) {
				bgr[n]+=sum[addr];
				sum[addr] = bgr[n];
				addr++;
			}
		}
	}
}


void sumY(unsigned int *sum, int w, int h) {
	
	dispatch_group_t _group = dispatch_group_create();
	dispatch_queue_t _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);
	
	dispatch_group_async(_group,_queue,^{
		sumY(sum,w,h,0,w>>2);
	});
	dispatch_group_async(_group,_queue,^{
		sumY(sum,w,h,(w>>2)*1,(w>>2)*2);
	});
	dispatch_group_async(_group,_queue,^{
		sumY(sum,w,h,(w>>2)*2,(w>>2)*3);
	});
	dispatch_group_async(_group,_queue,^{
		sumY(sum,w,h,(w>>2)*3,w);
	});
	
	dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
}

void blur(unsigned int *dst, unsigned int *src, unsigned int *sum, unsigned short *radius, int w, int h, int begin, int end) {

	for(int i=begin; i<end; i++) {
		for(int j=0; j<w; j++) {
			
			unsigned int addr = (i*w+j) ;
			
			if(radius[addr]==0) {
				dst[i*w+j] = src[i*w+j];
			}
			else {
				
				int top = i-radius[addr];
				if(top<0) top = 0;
				
				int bottom = i+radius[addr];
				if(bottom>h-1) bottom = h-1;
				
				int y = (bottom-top);
				
				int left = j-radius[addr];
				if(left<0) left = 0;
				
				int right = j+radius[addr];
				if(right>w-1) right = w-1; 
				int x = (right-left);
				
				double area = 1.0/(double)(x*y);
				
				int TL = (top*w+left)*BGR;
				int TR = (top*w+right)*BGR;
				int BL = (bottom*w+left)*BGR;
				int BR = (bottom*w+right)*BGR;
				
				unsigned int b = (sum[BR+0]-sum[BL+0]-sum[TR+0]+sum[TL+0])*area;
				unsigned int g = (sum[BR+1]-sum[BL+1]-sum[TR+1]+sum[TL+1])*area;
				unsigned int r = (sum[BR+2]-sum[BL+2]-sum[TR+2]+sum[TL+2])*area;
				
				dst[i*w+j] = 0xFF000000|CLAMP255(b)<<16|CLAMP255(g)<<8|CLAMP255(r);
			}
		}
	}
}

void blur(unsigned int *dst, unsigned int *src, unsigned int *sum, unsigned short *radius, int w, int h) {
	
	dispatch_group_t _group = dispatch_group_create();
	dispatch_queue_t _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH,0);

	dispatch_group_async(_group,_queue,^{
		blur(dst,src,sum,radius,w,h,0,h>>2);
	});
	dispatch_group_async(_group,_queue,^{
		blur(dst,src,sum,radius,w,h,(h>>2)*1,(h>>2)*2);
	});
	dispatch_group_async(_group,_queue,^{
		blur(dst,src,sum,radius,w,h,(h>>2)*2,(h>>2)*3);
	});
	dispatch_group_async(_group,_queue,^{
		blur(dst,src,sum,radius,w,h,(h>>2)*3,h);
	});
	
	dispatch_group_wait(_group,DISPATCH_TIME_FOREVER);
}

int main(int argc, char *argv[]) {

	@autoreleasepool {
		
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

			unsigned short *radius = new unsigned short[w*h];
			for(int i=0; i<h; i++) {
				for(int j=0; j<w; j++) {
					unsigned int addr = (i*w+j);
					short v = (depth[addr]&0xFF)-DEPTH_OFFSET;
					v>>=2;
					if(v<0) v = 0;
					else if(v>0xFF) v = 0xFF;
					radius[addr] = v;
				}
			}
			
			int bgr[BGR] = {0,0,0};
			
double then = CFAbsoluteTimeGetCurrent();
			
			sumX(sum,src,w,h);
			sumY(sum,w,h);
			blur(buf,src,sum,radius,w,h);
			
			sumX(sum,buf,w,h);
			sumY(sum,w,h);
			blur(dst,buf,sum,radius,w,h);

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
	