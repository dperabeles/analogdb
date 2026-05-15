import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Analog Archive",
  description: "Private analog photography archive."
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
