// This is image converter for libvm installer logo (https://github.com/Smok1e/oc-openos-libvm)
// The format is very simple, and stores every pixel in 4 bits:
//
// signature: 4 byte string - format isgnature, should be "LVMP"
// size_x: 2 byte unsigned - image width
// size_y: 2 byte unsigned - image height
// pallete: 48 bytes of 16 RGB colors - color pallete
// image data: each byte (except last, see above) stores 2 pixels indices
//
// If pixels count is odd then last 4 bits of byte will be zero, because you just can't write 1/2 byte to file
 
//------------------------------------

#include <SFML/Graphics.hpp>
#include <bitset>
#include <iostream>
#include <cstring>
#include <cmath>
#include <cerrno>
#include <vector>

//------------------------------------

template <typename obj_t> size_t write   (FILE* stream, const obj_t& obj);
unsigned char                    convert (const std::vector <sf::Color>& pallete, const sf::Color color);
unsigned char                    combine (const std::vector <sf::Color>& pallete, const sf::Color lft, const sf::Color rgt);

//------------------------------------

// Limit of colors that pallete contains (should be 16)
#define PALLETE_MAX 16

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

	std::vector <sf::Color> pallete;
	for (int i = 0, max = size.x*size.y; i < max; i++)
	{
		sf::Color color = image.getPixel (i%size.x, i/size.x); // X is index%width, Y is index//width
		
		auto iter = std::find (pallete.begin (), pallete.end (), color);
		if (iter == pallete.end ()) // Pallete does not contain this color
		{
			if (pallete.size () >= PALLETE_MAX)
			{
				printf ("Warning: Pallete limit (%d) exceeded, some colors may not be displayed.\n", PALLETE_MAX);
				break;
			}

			pallete.push_back (color);
		}
	}

	FILE* file = fopen (argv[2], "wb");
	if (!file)
	{
		printf ("Failed to write '%s': %s\n", argv[2], strerror (errno));
		return 0;
	}

	write (file, SIGNATURE ("LVMP")); // Format signature
	write (file, static_cast <unsigned __int16> (size.x));
	write (file, static_cast <unsigned __int16> (size.y));

	pallete.resize (PALLETE_MAX);
	for (size_t i = 0; i < PALLETE_MAX; i++)
	{
		write (file, pallete[i].r);
		write (file, pallete[i].g);
		write (file, pallete[i].b);
	}

	for (int x = 0; x < size.x; x++)
	for (int y = 0; y < size.y; y += 2)
		write (file, combine (pallete, image.getPixel (x, y), y+1 < size.y? image.getPixel (x, y+1): sf::Color::Black));

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

unsigned char convert (const std::vector <sf::Color>& pallete, const sf::Color color)
{
	const auto& iter = std::find (pallete.begin (), pallete.end (), color);
	if (iter == pallete.end ())
		return 0; // Color is not in the pallete

	return static_cast <unsigned char> (std::distance (pallete.begin (), iter)); 
}

unsigned char combine (const std::vector <sf::Color>& pallete, const sf::Color lft, const sf::Color rgt)
{
	return (convert (pallete, lft) << 4) | convert (pallete, rgt);
}

//------------------------------------