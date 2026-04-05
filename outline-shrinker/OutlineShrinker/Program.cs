using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Drawing;
using Console = Colorful.Console;

namespace OutlineShrinker
{
    class Program
    {
        static Bitmap bm;

        static string outputPath = "output.png";

        static void ComRead()
        {
            Console.Write("   Image name to read: ");
            string path = Console.ReadLine();

            try
            {
                Image inputImg = Image.FromFile(path);
                bm = new Bitmap(inputImg);
                width = bm.Width;
                height = bm.Height;
                Console.WriteLine("    Width: " + width.ToString()
                    + "\n    Height: " + height.ToString()
                    + "\n    Amount: " + (width * height / 1000).ToString() + "k pixels");
                SayDone();
            }
            catch
            {
                SayError();
            }
        }

        static void ComSave()
        {
            try
            {
                Console.WriteLine("   Writing to \"" + outputPath + "\"");
                bm.Save(outputPath, System.Drawing.Imaging.ImageFormat.Png);
                SayDone();
            }
            catch
            {
                SayError();
            }
        }

        static void ComMinalpha()
        {
            Console.WriteLine("   Current minimal mask alpha is {0}", maskMinAlpha);
            Console.Write("   New alpha: "); maskMinAlpha = Convert.ToInt32(Console.ReadLine());
        }

        static void ComMaxRgbAverage()
        {
            Console.WriteLine("   Current maximal RGB average is {0}", maxRgbAverage);
            Console.Write("   New average: "); maxRgbAverage = Convert.ToInt32(Console.ReadLine());
        }

        static void ComFat()
        {
            try
            {
                Console.Write("   Amount of layers to add: "); int n = Convert.ToInt32(Console.ReadLine());
                for(int i = 0; i < n; i++)
                {
                    CreateMask();
                    FindOutline();
                    addOutline();
                    SayDone();
                }
            }
            catch
            {
                SayError();
            }
        }

        static void ComThin()
        {
            try
            {
                Console.Write("   Amount of layers to remove: "); int n = Convert.ToInt32(Console.ReadLine());
                for(int i = 0; i < n; i++)
                {
                    CreateMask();
                    FindOutline();
                    removeOutline();
                    SayDone();
                }
            }
            catch
            {
                SayError();
            }
        }

        static void SayDone()
        {
            Console.WriteLine(" [Done]\n");
            Console.Beep(1000, 120);

        }

        static void SayError()
        {
            Console.WriteLine(" [Error has occured]\n");
            WrongSound();
        }

        static void WrongSound()
        {
            Console.Beep(1000, 120);
            Console.Beep(700, 150);
        }

        static void Main(string[] args)
        {
            Console.BackgroundColor = Color.FromArgb(10, 15, 25);
            Console.Clear();
            Console.Beep(1200, 150);
            Console.WriteLine(" Available commands:");
            Console.WriteLine("   read\n   min_alpha\n   max_rgb_average\n   fat\n   thin\n   save\n   quit\n");
            bool stop = false;
            while(!stop)
            {
                Console.Write("> "); string s = Console.ReadLine();
                s = s.ToLowerInvariant();
                switch(s)
                {
                    case "quit":
                        Console.WriteLine(" Exit?" +
                            "\n\n              [Y/N]", Color.Crimson);
                        Console.Beep(300, 150);
                        retry0:;
                        Console.Write("> "); string ch = Console.ReadLine();
                        if(ch.ToLowerInvariant() == "y")
                        {
                            stop = true;
                            Console.Write("\n      Bye!");
                            System.Threading.Thread.Sleep(600);
                        }
                        else if(ch.ToLowerInvariant() != "n")
                        {
                            goto retry0;
                        }
                        break;

                    case "read":
                        ComRead();
                        break;

                    case "save":
                        ComSave();
                        break;

                    case "fat":
                        ComFat();

                        break;
                    case "thin":
                        ComThin();
                        break;

                    case "min_alpha":
                        ComMinalpha();
                        break;

                    case "max_rgb_average":
                        ComMaxRgbAverage();
                        break;

                    default:
                        Console.WriteLine(" [Don't type arguments]\n");
                        WrongSound();
                        break;
                }
            }
        }
        static readonly Color empty = Color.FromArgb(0, 0, 0, 0);
        static int maskMinAlpha = 30;
        static int maxRgbAverage = 227;
        static int width, height;

        static bool[,] mask;
        static outlinePixel[] outlinePixels;
        static bool[,] outlineMask;


        static void CreateMask()
        {
            int width = bm.Width, height = bm.Height;
            mask = new bool[width, height];

            Color col;

            for(int i = 0; i < width; i++)
                for(int j = 0; j < height; j++)
                {
                    col = bm.GetPixel(i, j);
                    if(col.A >= maskMinAlpha && (col.R + col.G + col.B) < maxRgbAverage * 3)
                    {
                        mask[i, j] = true;
                    }
                    else
                    {
                        mask[i, j] = false;
                        bm.SetPixel(i, j, empty);
                    }
                }
        }

        static void FindOutline()
        {
            outlinePixels = new outlinePixel[width * height];
            outlineMask = new bool[width, height];

            int k = 0;

            for(int i = 0; i < width; i++)
                for(int j = 0; j < height; j++)
                {
                    if(IsSolid(i, j))
                    {
                        bool up = IsSolid(i, j - 1),
                            right = IsSolid(i + 1, j),
                            down = IsSolid(i, j + 1),
                            left = IsSolid(i - 1, j);

                        if(!(up && right && down && left))
                        {
                            int x_norm = 0;
                            int y_norm = 0;

                            if(up)
                            {
                                if(!down)
                                {
                                    y_norm = 1;
                                }
                            }
                            else
                            {
                                y_norm = -1;
                            }

                            if(left)
                            {
                                if(!right)
                                {
                                    x_norm = 1;
                                }
                            }
                            else
                            {
                                x_norm = -1;
                            }

                            outlinePixels[k] = new outlinePixel(i, j, x_norm, y_norm);
                            outlineMask[i, j] = true;
                            k++;
                        }
                    }
                }
        }

        static bool IsSolid(int x, int y)
        {
            if(x >= width || x < 0 || y >= height || y < 0)
                return false;
            return mask[x, y];
        }

        static bool IsOutline(int x, int y)
        {
            if(x >= width || x < 0 || y >= height || y < 0)
                return false;
            return outlineMask[x, y];
        }

        public static void removeOutline()
        {
            foreach(outlinePixel pix in outlinePixels)
            {
                Color col = bm.GetPixel(pix.X, pix.Y);
                bm.SetPixel(pix.X, pix.Y, Color.FromArgb(15, col.R, col.G, col.B));
            }
        }

        public static void addOutline()
        {

            for(int i = 0; i < width; i++)
                for(int j = 0; j < height; j++)
                    if(!IsSolid(i, j))
                    {
                        bool up = IsOutline(i, j - 1),
                            right = IsOutline(i + 1, j),
                            down = IsOutline(i, j + 1),
                            left = IsOutline(i - 1, j - 1);

                        if(up || right || down || left)
                        {
                            int n = 0;
                            Color col;
                            int r = 0, g = 0, b = 0;

                            if(up)
                            {
                                col = bm.GetPixel(i, j - 1);
                                r += col.R;
                                g += col.G;
                                b += col.B;
                                //r += col.R * col.R;
                                //g += col.G * col.G;
                                //b += col.B * col.B;
                                n++;
                            }
                            if(right)
                            {
                                col = bm.GetPixel(i + 1, j);
                                r += col.R;
                                g += col.G;
                                b += col.B;
                                //r += col.R * col.R;
                                //g += col.G * col.G;
                                //b += col.B * col.B;
                                n++;
                            }
                            if(down)
                            {
                                col = bm.GetPixel(i, j + 1);
                                r += col.R;
                                g += col.G;
                                b += col.B;
                                //r += col.R * col.R;
                                //g += col.G * col.G;
                                //b += col.B * col.B;
                                n++;
                            }
                            if(left)
                            {
                                col = bm.GetPixel(i - 1, j);
                                r += col.R;
                                g += col.G;
                                b += col.B;
                                //r += col.R * col.R;
                                //g += col.G * col.G;
                                //b += col.B * col.B;
                                n++;
                            }

                            if(n != 0)
                            {
                                //r = (int)Math.Sqrt((float)r / n);
                                //g = (int)Math.Sqrt((float)r / n);
                                //b = (int)Math.Sqrt((float)r / n);
                                r = r / n;
                                g = g / n;
                                b = b / n;
                                bm.SetPixel(i, j, Color.FromArgb(255, r, g, b));
                            }
                        }
                    }
        }


        public struct outlinePixel
        {
            public int X, Y;
            public int X_norm, Y_norm;

            public outlinePixel(int x, int y, int x_norm, int y_norm)
            {
                X = x; Y = y;
                X_norm = x_norm; Y_norm = y_norm;
            }
        }
    }
}