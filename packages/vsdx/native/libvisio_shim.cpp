// C ABI shim over libvisio, used as an *oracle* for the Dart parser's
// differential tests (see test/libvisio_diff_test.dart).
//
// libvisio renders a Visio document by driving a librevenge
// RVNGDrawingInterface. We feed it the SVG generator and hand the resulting
// per-page SVG back to Dart over a tiny C ABI so `dart:ffi` can call it.
//
// Build with native/build.sh (requires `brew install libvisio`).

#include <cstdlib>
#include <cstring>
#include <string>

#include <librevenge/librevenge.h>
#include <librevenge-generators/librevenge-generators.h>
#include <librevenge-stream/librevenge-stream.h>
#include <libvisio/VisioDocument.h>

namespace
{
// One page's SVG separated from the next by this sentinel so Dart can split.
const char *const kPageSeparator = "\n<!--__VSDX_PAGE__-->\n";

const char *toSvg(const unsigned char *data, unsigned long len, bool stencils)
{
  try
  {
    librevenge::RVNGStringStream input(data, static_cast<unsigned int>(len));
    if (!libvisio::VisioDocument::isSupported(&input))
      return nullptr;

    librevenge::RVNGStringVector pages;
    librevenge::RVNGSVGDrawingGenerator generator(pages, "svg");
    const bool parsed = stencils
                            ? libvisio::VisioDocument::parseStencils(&input, &generator)
                            : libvisio::VisioDocument::parse(&input, &generator);
    if (!parsed)
      return nullptr;

    std::string out;
    for (unsigned i = 0; i < pages.size(); ++i)
    {
      if (i != 0)
        out += kPageSeparator;
      out += pages[i].cstr();
    }

    char *buf = static_cast<char *>(std::malloc(out.size() + 1));
    if (!buf)
      return nullptr;
    std::memcpy(buf, out.c_str(), out.size() + 1);
    return buf;
  }
  catch (...)
  {
    return nullptr;
  }
}
} // namespace

extern "C"
{

  // Parse [data]/[len] (a .vsdx blob) with libvisio and return the concatenated
  // per-page SVG (pages joined by the sentinel above). Returns nullptr when the
  // input isn't a supported Visio document or parsing fails. The caller must
  // release the result with vsdx_shim_free.
  const char *vsdx_shim_to_svg(const unsigned char *data, unsigned long len)
  {
    return toSvg(data, len, false);
  }

  // Equivalent to libvisio's vss2raw/vss2xhtml path: expose stencil masters
  // as pages instead of parsing only the placeholder drawing page.
  const char *vsdx_shim_stencils_to_svg(const unsigned char *data, unsigned long len)
  {
    return toSvg(data, len, true);
  }

  void vsdx_shim_free(const char *p)
  {
    if (p)
      std::free(const_cast<char *>(p));
  }

} // extern "C"
