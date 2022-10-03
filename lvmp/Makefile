# Change this value to your SFML directory, if you need to compile this for some reason...
SFML_DIR=C:\Users\Fedor\Lib\SFML-2.5.1

all:
	@echo Compiling lvmp.exe...
	g++ .\src\main.cpp -o .\bin\lvmp.exe -I $(SFML_DIR)\include -L $(SFML_DIR)\lib -lsfml-graphics -lsfml-window -lsfml-system -static-libgcc -static-libstdc++
	
	@echo Copying dependeicies...
	xcopy /Y /s $(SFML_DIR)\bin .\bin
	
	@echo Seems like everything is ok.