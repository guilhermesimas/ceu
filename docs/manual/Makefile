all:
	rm -Rf out/
	mkdir -p out/v0.8/
	cd v0.8/ && lua5.3 ../md-toc.lua v0.8 && pandoc manual-toc-v0.8.md -o index.html && mv index.html ../out/v0.8/ && cp *.png ../out/v0.8/
	mkdir -p out/v0.10/
	cd v0.10/ && lua5.3 ../md-toc.lua v0.10 && pandoc manual-toc-v0.10.md -o index.html && mv index.html ../out/v0.10/ && cp *.png ../out/v0.10/
	cd v0.20/ && mkdocs build --clean && mkdocs2pandoc > ceu-v0.20.md && pandoc ceu-v0.20.md -o ceu-v0.20.pdf && mv site/ ../out/v0.20/
