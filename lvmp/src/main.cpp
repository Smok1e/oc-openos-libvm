// This is image converter for libvm installer logo (https://github.com/Smok1e/oc-openos-libvm)
// The format is very simple, and stores every pixel in 4 bits:
//
// format signature: 4 byte string (should be "LVMP")
// image width: 2 byte unsigned
// image height: 2 byte unsingned
// image data: each byte (except last, see above) stores 2 pixels in 16 variations of colors from 0x0 to 0xF
//
// If pixels count is odd then last 4 bits of byte will be zero, because you just can't write 1/2 byte to file
 
//------------------------------------

#include <SFML/Graphics.hpp>
#include <bitset>
#include <iostream>
#include <cstring>
#include <cmath>
#include <cerrno>

//------------------------------------

template <typename obj_t> size_t write   (FILE* stream, const obj_t& obj);
unsigned char                    convert (const sf::Color color);
unsigned char                    combine (const sf::Color lft, const sf::Color rgt);

//------------------------------------

// Makes 32 bit number from a 4 byte string
#define SIGNATURE(signature) *reinterpret_cast <const unsigned __int32*> (signature)

//------------------------------------

int main (int argc, char* argv[])
{
	if (argc < 3)
	{
		printf ("Usage: lvmp <source filename> <result filename>");
		return 0;
	}

	sf::Image image;
	if (!image.loadFromFile (argv[1]))
		return 0;

	sf::Vector2u size = image.getSize ();
	const sf::Uint32* data = reinterpret_cast <const sf::Uint32*> (image.getPixelsPtr ()-1); // WTF???

	FILE* file = fopen (argv[2], "wb");
	if (!file)
	{
		printf ("Failed to write '%s': %s\n", argv[2], strerror (errno));
		return 0;
	}

	write (file, SIGNATURE ("LVMP")); // Format signature
	write (file, static_cast <unsigned __int16> (size.x));
	write (file, static_cast <unsigned __int16> (size.y));

	for (int x = 0; x < size.x; x++)
	for (int y = 0; y < size.y; y += 2)
		write (file, combine (image.getPixel (x, y), y+1 < size.y? image.getPixel (x, y+1): sf::Color::Black));

	printf ("The result is saved as '%s'\n", argv[2]);
	fclose (file);
	return 0;
}

//------------------------------------

template <typename obj_t>
size_t write (FILE* file, const obj_t& obj)
{
	return fwrite (&obj, sizeof (obj_t), 1, file);
}

unsigned char convert (const sf::Color color)
{
	return static_cast <unsigned char> (floor ((static_cast <double> (color.r+color.g+color.b) / 3.0) / 0xFF * 0xF)); 
}

unsigned char combine (const sf::Color lft, const sf::Color rgt)
{
	return (convert (lft) << 4) | convert (rgt);
}

//------------------------------------