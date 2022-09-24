#import <Foundation/Foundation.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
namespace stb_image {
	#import "./libs/stb_image.h"
	#import "./libs/stb_image_write.h"
}

const int DEPTH_OFFSET = 4;
const float DEPTH_SCALE = 16.0;

int main(int argc, char *argv[]) {

	@autoreleasepool {
		
		int info[3];	
		float *map = (float *)stb_image::stbi_load("./pointcloud.png",info,info+1,info+2,4);
		
		if(map) {
			
			if(info[0]==256&&info[1]==193) {
				
				const int w = info[0]*7.5;
				const int h = (info[1]-1)*7.5;
				
				NSLog(@"%d,%d",w,h);
				
				const float sx = (info[0]-1)/(float)(w-1);
				const float sy = (info[1]-2)/(float)(h-1);
				
				unsigned int *depth = new unsigned int[w*h];

				for(int i=0; i<h; i++) {
					
					const float fy = i*sy;
					const int iy = fy;
					const float dy = (fy-iy);
					const float ey = 1.0-dy;
					
					float *s = (map+(iy*info[0]));
					
					for(int j=0; j<w; j++) {
						
						const float fx = j*sx;
						const int ix = fx;
						const float dx = (fx-ix);
						const float ex = 1.0-dx;
						
						const float c1 = ex*ey;
						const float c2 = dx*ey;
						const float c3 = dx*dy;
						const float c4 = ex*dy;
						
						float *f = s+ix;
						
						float d = (*f)*c1;
						if(dx) f++;
						d+=(*f)*c2;
						if(dy) f+=info[0];
						d+=(*f)*c3;
						if(dx) f--;
						d+=(*f)*c4;
						
						int z = DEPTH_OFFSET+d*DEPTH_SCALE;
						if(z>=0xFF) z = 0xFF;
						
						depth[i*w+j] = 0xFF000000|z<<16|z<<8|z; // offset 1
					}
				}
				
				stb_image::stbi_write_png("./depth.png",w,h,4,(void const*)depth,w<<2);
				delete[] depth;

			}
			
			delete[] map;
		}
	}
}
	