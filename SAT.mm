#import <Foundation/Foundation.h>

void echo(unsigned short *p, int w, int h) {
	for(int k=0; k<w*h; k++) {
		printf("%03d,",p[k]);
		if(k%w==w-1) printf("\n");
	}
	printf("\n");
}

int main(int argc, char *argv[]) {
	@autoreleasepool {
		
		int W = 16;
		int H = 9;
		
		unsigned short *b = new unsigned short[(W+1)*(H+1)];
		for(int k=0; k<(W+1)*(H+1); k++) b[k] = 0;
		
		for(int i=0; i<H; i++) {
			unsigned short v = 0;
			for(int j=0; j<W; j++) {
				b[(i+1)*(W+1)+(j+1)]=1;
			}
		}
		echo(b,W+1,H+1);
		
		unsigned short *sum = new unsigned short[(W+1)*(H+1)];

		for(int i=0; i<H+1; i++) {
			unsigned short v = 0;
			for(int j=0; j<W+1; j++) {
				sum[i*(W+1)+j]+=(v+=b[i*(W+1)+j]);
			}
		}
		
		for(int j=0; j<W+1; j++) {
			unsigned short v = 0;
			for(int i=0; i<H+1; i++) {
				sum[i*(W+1)+j]=(v+=sum[i*(W+1)+j]);
			}
		}
		echo(sum,W+1,H+1);

		const int radius = 3;

		const int x = W>>1;
		const int y = H>>1;
		
		int left = x - radius;
		int right = x + radius + 1;
		
		if(left<0) left=0;
		if(right>W) right = W;
		
		
		int top = y - radius;
		int bottom = y + radius + 1;
		
		if(top<0) top=0;
		if(bottom>H) bottom = H;
		
		
		NSLog(@"%d,%d,%d,%d",left,top,right,bottom);
		
		int area = ((right-left))*((bottom-top));
		NSLog(@"%d",area);

		NSLog(@"%d,%d,%d,%d",sum[top*(W+1)+left],sum[top*(W+1)+right],sum[bottom*(W+1)+left],sum[bottom*(W+1)+right]);
		NSLog(@"%f",(sum[top*(W+1)+left]-sum[top*(W+1)+right]-sum[bottom*(W+1)+left]+sum[bottom*(W+1)+right])/(double)area);
		

	}
}