#import <Foundation/Foundation.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
namespace stb_image {
	#import "./libs/stb_image.h"
	#import "./libs/stb_image_write.h"
}

#import "SAT.h"

int main(int argc, char *argv[]) {

	@autoreleasepool {
		
		const char *SRC = "./texture.jpg";
		const char *MAP = "./depth.png";
		const char *DST = "./blur.png";
		
		
		int info[3];	
		unsigned int *src = (unsigned int *)stb_image::stbi_load(SRC,info,info+1,info+2,4);
		
		if(src) {
			
			const int w = info[0];
			const int h = info[1];
			
			unsigned int *_depth = (unsigned int *)stb_image::stbi_load(MAP,info,info+1,info+2,4);
			unsigned char *depth = new unsigned char[w*h];
			for(int i=0; i<h; i++) {
				for(int j=0; j<w; j++) {
					depth[i*w+j] = _depth[i*w+j]&0xFF;
				}
			}
			 
double then = CFAbsoluteTimeGetCurrent();

			SAT *sat = new SAT(w,h);
			sat->scale(0.175);
			sat->forcus(-12);
			sat->blur(src,depth);

NSLog(@"%f",CFAbsoluteTimeGetCurrent()-then);
			
			stb_image::stbi_write_png(DST,w,h,4,(void const*)sat->bytes(),w<<2);
			
			delete sat;
			delete[] src;
			delete[] depth;
			delete[] _depth;

		}
	}
}
	