#import <Foundation/Foundation.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
namespace stb_image {
	#import "./libs/stb_image.h"
	#import "./libs/stb_image_write.h"
}

#define CLAMP255(v) ((v>0xFF)?0xFF:(v<0)?0:v)
#define BGR 3

int main(int argc, char *argv[]) {

	@autoreleasepool {
		
		int info[3];	
		unsigned int *xy = (unsigned int *)stb_image::stbi_load("./images/test.png",info,info+1,info+2,4);
		
		if(xy) {
			
			const int radius = 8;

			const int w = info[0];
			const int h = info[1];
			
			unsigned int *yx = new unsigned int[w*h];
			
			double then = CFAbsoluteTimeGetCurrent();
			
			unsigned int *sum = new unsigned int[w*h*BGR];
			unsigned int *ptr = xy;
			
			int bgr[BGR] = {0,0,0};
			
			for(int i=0; i<h; i++) {
				for(int n=0; n<BGR; n++) bgr[n]=0;
				for(int j=0; j<w; j++) {
					unsigned int pixel = xy[i*w+j];
					unsigned int addr = (i*w+j)*BGR;
					for(int n=0; n<BGR; n++) {
						sum[addr++] = (bgr[n]+=((pixel>>(0x10-(n<<3)))&0xFF));
					}
				}
			}
			
			for(int j=0; j<w; j++) {
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
			
			for(int i=0; i<h; i++) {
				for(int j=0; j<w; j++) {
					
					if(radius==0) {
						yx[i*w+j] = xy[i*w+j];
					}
					else {
						
						int top = i-radius;
						if(top<0) top = 0;
						
						int bottom = i+radius;
						if(bottom>h-1) bottom = h-1;
						
						int y = (bottom-top);
						
						int left = j-radius;
						if(left<0) left = 0;
						
						int right = j+radius;
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
						
						yx[i*w+j] = 0xFF000000|CLAMP255(b)<<16|CLAMP255(g)<<8|CLAMP255(r);
					}
					
				}
			}
			
			for(int i=0; i<h; i++) {
				for(int n=0; n<BGR; n++) bgr[n]=0;
				for(int j=0; j<w; j++) {
					unsigned int pixel = yx[i*w+j];
					unsigned int addr = (i*w+j)*BGR;
					for(int n=0; n<BGR; n++) {
						sum[addr++] = (bgr[n]+=((pixel>>(0x10-(n<<3)))&0xFF));
					}
				}
			}
			
			for(int j=0; j<w; j++) {
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
			
			for(int i=0; i<h; i++) {
				for(int j=0; j<w; j++) {
					
					if(radius==0) {
						xy[i*w+j] = yx[i*w+j];
					}
					else {
						
						int top = i-radius;
						if(top<0) top = 0; 
						
						int bottom = i+radius;
						if(bottom>h-1) bottom = h-1; 
						
						int y = (bottom-top);
						
						int left = j-radius;
						if(left<0) left = 0; 
						
						int right = j+radius;
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
						
						xy[i*w+j] = 0xFF000000|CLAMP255(b)<<16|CLAMP255(g)<<8|CLAMP255(r);
					}
				}
			}
			
			NSLog(@"%f",CFAbsoluteTimeGetCurrent()-then);

			stb_image::stbi_write_png("./blur.png",w,h,4,(void const*)xy,w<<2);
			
			delete[] sum;
			
			delete[] yx;
			delete[] xy;
		}
	}
}
	